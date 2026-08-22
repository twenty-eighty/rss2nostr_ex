defmodule Rss2Nostr.Nostr.Blossom.PostImages do
  @moduledoc false

  require Logger

  alias Rss2Nostr.Nostr.{Blossom, Blossom.Client, NIP92, Signer}
  alias Rss2Nostr.Posts
  alias Rss2Nostr.Processing.{ImageExtractor, VideoProbe}
  alias Rss2Nostr.Sources.Source

  @spec ensure_post_images(Rss2Nostr.Posts.Post.t(), Signer.signer() | binary()) ::
          {:ok, Rss2Nostr.Posts.Post.t()} | {:error, term()}
  def ensure_post_images(post, signer) do
    signer = normalize_signer(signer)
    post = Posts.preload_images(post)
    {post, mapping} = stamp_hosted_images(post)

    Signer.with_open(signer, fn open_signer ->
      {post, mapping, errors} = upload_pending_images(post, mapping, open_signer)
      {:ok, post} = apply_image_mapping(post, mapping)
      post = Posts.preload_images(post)

      case {pending_image_urls(post), errors} do
        {[], _} ->
          {:ok, post}

        {_pending, [reason | _]} ->
          message = "Blossom upload failed: #{Client.format_error(reason)}"
          Logger.warning("[Blossom] #{message} (post #{post.id})")
          _ = Posts.update_post(post, %{last_error: message})
          {:error, reason}

        {_pending, []} ->
          {:error, :images_pending}
      end
    end)
  end

  @spec stamp_hosted_images(Rss2Nostr.Posts.Post.t()) ::
          {Rss2Nostr.Posts.Post.t(), %{String.t() => String.t()}}
  def stamp_hosted_images(post) do
    post = post |> Posts.preload_source() |> Posts.preload_images()

    uploaded_urls =
      MapSet.new(for image <- post.images, present?(image.uploaded_url), do: image.uploaded_url)

    uploaded_by_canonical =
      Map.new(
        for image <- post.images,
            present?(image.uploaded_url),
            do: {ImageExtractor.normalize_url(image.original_url), image}
      )

    mapping =
      Enum.reduce(post.images, %{}, fn image, acc ->
        canonical = ImageExtractor.normalize_url(image.original_url)
        sibling = uploaded_by_canonical[canonical]

        cond do
          present?(image.uploaded_url) ->
            Map.put(acc, image.original_url, image.uploaded_url)

          Blossom.already_hosted?(image.original_url) or keep_original_media?(post, image.original_url) or
              MapSet.member?(uploaded_urls, image.original_url) ->
            {:ok, updated} = Posts.mark_image_uploaded(image, image.original_url, hosted_attrs(image))
            Map.put(acc, updated.original_url, updated.uploaded_url)

          match?(%{uploaded_url: url} when is_binary(url), sibling) ->
            {:ok, updated} =
              Posts.mark_image_uploaded(image, sibling.uploaded_url, copy_upload_attrs(sibling))

            Map.put(acc, updated.original_url, updated.uploaded_url)

          true ->
            acc
        end
      end)

    mapping =
      if present?(post.image) and
           (Blossom.already_hosted?(post.image) or keep_original_media?(post, post.image)) do
        Map.put_new(mapping, post.image, post.image)
      else
        mapping
      end

    {:ok, post} = apply_image_mapping(post, mapping)
    {Posts.preload_images(post), mapping}
  end

  @spec pending_images?(Rss2Nostr.Posts.Post.t()) :: boolean()
  def pending_images?(post) do
    post
    |> Posts.preload_images()
    |> pending_image_urls()
    |> Enum.any?()
  end

  defp upload_pending_images(post, mapping, open_signer) do
    targets = pending_image_records(post)

    Enum.reduce(targets, {post, mapping, []}, fn image, {post, mapping, errors} ->
      case Blossom.upload_from_url(image.original_url, signer: open_signer) do
        {:ok, result} ->
          {:ok, updated} =
            Posts.mark_image_uploaded(
              image,
              result.url,
              NIP92.stored_attrs(result, alt: image.alt_text)
            )

          {Posts.preload_images(post), Map.put(mapping, updated.original_url, result.url), errors}

        {:error, reason} ->
          {post, mapping, [reason | errors]}
      end
    end)
  end

  defp apply_image_mapping(post, mapping) when mapping == %{}, do: {:ok, post}

  defp apply_image_mapping(post, mapping) do
    content = ImageExtractor.replace_image_urls(post.content, mapping)
    image = Map.get(mapping, post.image || "", post.image)

    Posts.update_post(post, %{content: content, image: image, last_error: nil})
  end

  defp pending_image_records(post) do
    existing = post.images || []
    known = MapSet.new(existing, & &1.original_url)

    featured =
      if present?(post.image) and not MapSet.member?(known, post.image) and
           is_nil(mapping_or_hosted(post.image, existing)) do
        case Posts.create_image(%{post_id: post.id, original_url: post.image}) do
          {:ok, image} -> [image]
          {:error, _} -> []
        end
      else
        []
      end

    uploaded_urls = uploaded_url_set(existing)

    (featured ++ existing)
    |> Enum.reject(fn image ->
      image_ready?(image, uploaded_urls)
    end)
  end

  defp pending_image_urls(post) do
    images = post.images || []
    uploaded_urls = uploaded_url_set(images)

    from_records =
      for image <- images,
          not image_ready?(image, uploaded_urls),
          do: image.original_url

    featured =
      if present?(post.image) and is_nil(mapping_or_hosted(post.image, images)) do
        [post.image]
      else
        []
      end

    Enum.uniq(featured ++ from_records)
  end

  defp uploaded_url_set(images) do
    MapSet.new(for image <- images, present?(image.uploaded_url), do: image.uploaded_url)
  end

  defp image_ready?(image, uploaded_urls) do
    present?(image.uploaded_url) or Blossom.already_hosted?(image.original_url) or
      MapSet.member?(uploaded_urls, image.original_url)
  end

  defp keep_original_media?(%{source: %Source{} = source}, url) do
    ImageExtractor.video_url?(url) and not Source.mirror_media?(source)
  end

  defp keep_original_media?(_, _), do: false

  defp mapping_or_hosted(url, images) do
    cond do
      Blossom.already_hosted?(url) ->
        url

      match = Enum.find(images, &(&1.original_url == url and present?(&1.uploaded_url))) ->
        match.uploaded_url

      match = Enum.find(images, &(present?(&1.uploaded_url) and &1.uploaded_url == url)) ->
        match.uploaded_url

      true ->
        nil
    end
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: false

  defp hosted_attrs(image) do
    caption = ImageExtractor.parse_media_caption(image.caption)
    probed = probe_media(image, caption)
    mime = probed[:type] || image.mime_type || Client.guess_content_type(image.original_url)
    duration = probed[:duration] || caption.duration
    size = probed[:size] || caption.size || image.file_size
    dim = probed[:dim] || image.dim

    NIP92.stored_attrs(
      %{
        url: image.original_url,
        sha256: image.sha256,
        size: size,
        type: mime,
        nip94: []
      },
      alt: image.alt_text,
      duration: duration,
      dim: dim,
      bitrate: probed[:bitrate]
    )
    |> Map.merge(%{
      imeta:
        case image.imeta do
          pairs when is_list(pairs) and pairs != [] ->
            pairs

          _ ->
            NIP92.pairs_from_url(image.original_url,
              alt: image.alt_text,
              mime: mime,
              duration: duration,
              size: size,
              dim: dim,
              bitrate: probed[:bitrate]
            )
        end
    })
  end

  defp probe_media(image, caption) do
    url = image.original_url

    if ImageExtractor.video_url?(url) or ImageExtractor.audio_url?(url) do
      kind = if ImageExtractor.audio_url?(url), do: "audio", else: "video"
      Logger.info("Probing #{kind} metadata at #{url}")

      VideoProbe.probe(url,
        duration: caption.duration,
        size: caption.size || image.file_size,
        type: image.mime_type
      )
    else
      %{}
    end
  end

  defp copy_upload_attrs(image) do
    %{
      sha256: image.sha256,
      mime_type: image.mime_type,
      file_size: image.file_size,
      dim: image.dim,
      thumb: image.thumb,
      imeta: image.imeta || []
    }
  end

  defp normalize_signer({:private_key, key}), do: {:private_key, key}
  defp normalize_signer({:bunker, value}), do: {:bunker, value}
  defp normalize_signer(key) when is_binary(key), do: {:private_key, key}
end
