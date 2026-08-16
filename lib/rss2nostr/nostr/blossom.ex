defmodule Rss2Nostr.Nostr.Blossom do
  @moduledoc """
  Blossom blob storage (BUD-01 / BUD-02 / BUD-11).

  Uploads images and audio with `PUT /upload` and a kind 24242 authorization event.
  This replaces NIP-96.
  """

  require Logger

  alias Rss2Nostr.HTTP
  alias Rss2Nostr.Nostr.{NIP92, Signer}
  alias Rss2Nostr.Posts
  alias Rss2Nostr.Processing.ImageExtractor

  @kind_auth 24242
  @auth_ttl_seconds 300
  @image_download_ms 30_000
  @audio_download_ms 180_000
  @image_upload_ms 60_000
  @audio_upload_ms 180_000

  @type upload_result :: %{
          url: String.t(),
          sha256: String.t() | nil,
          size: integer() | nil,
          type: String.t() | nil,
          nip94: list(),
          dimensions: {integer(), integer()} | nil
        }

  @doc """
  Configured Blossom server from `NOSTR_UPLOAD_ENDPOINT`, or `nil`.
  """
  @spec configured_server() :: String.t() | nil
  def configured_server do
    case Application.get_env(:rss2nostr, :nostr, []) |> Access.get(:upload_endpoint) do
      nil ->
        nil

      "" ->
        nil

      url when is_binary(url) ->
        case String.trim(url) do
          "" -> nil
          trimmed -> String.trim_trailing(trimmed, "/")
        end

      _ ->
        nil
    end
  end

  @doc """
  The configured upload server, or an empty list if none is set.
  There are no fallback servers.
  """
  @spec servers() :: [String.t()]
  def servers do
    case configured_server() do
      nil -> []
      endpoint -> [endpoint]
    end
  end

  @doc """
  True when `url` is already hosted on the given Blossom server
  (defaults to `NOSTR_UPLOAD_ENDPOINT`).
  """
  @spec already_hosted?(String.t(), String.t() | nil) :: boolean()
  def already_hosted?(url, server \\ nil)

  def already_hosted?(url, server) when is_binary(url) do
    image_host = server_host(url)
    blossom_host = server_host(server || configured_server())

    is_binary(image_host) and is_binary(blossom_host) and image_host == blossom_host
  end

  def already_hosted?(_, _), do: false

  @doc """
  BUD-02 upload URL for a server base (`https://host` → `https://host/upload`).
  """
  @spec upload_url(String.t()) :: String.t()
  def upload_url(server_url) do
    base = server_url |> String.trim() |> String.trim_trailing("/")

    if String.ends_with?(base, "/upload") do
      base
    else
      base <> "/upload"
    end
  end

  @doc """
  BUD-11 `Authorization` header for a signed kind 24242 event.
  """
  @spec authorization_header(map()) :: String.t()
  def authorization_header(signed_event) do
    json =
      Jason.encode!(%{
        id: signed_event.id,
        pubkey: signed_event.pubkey,
        created_at: signed_event.created_at,
        kind: signed_event.kind,
        tags: signed_event.tags,
        content: signed_event.content,
        sig: signed_event.sig
      })

    # route96 and most Blossom servers decode with standard Base64 (padding
    # included). BUD-11's base64url form is rejected as HTTP 400.
    "Nostr " <> Base.encode64(json)
  end

  @doc """
  HEAD `/upload` to see if a Blossom server is reachable.
  """
  @spec probe_server(String.t()) :: {:ok, integer()} | {:error, term()}
  def probe_server(server_url) do
    case HTTP.head(upload_url(server_url), receive_timeout: 10_000, retry: false) do
      {:ok, %{status: status}} when status in [200, 201, 400, 401, 403, 411, 413, 415] ->
        {:ok, status}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, exception} ->
        {:error, exception}
    end
  end

  @doc """
  Uploads a local file.

  Options:
  - `:private_key` (required)
  - `:server` — Blossom base URL (default: `NOSTR_UPLOAD_ENDPOINT` only)
  - `:content_type`
  """
  def upload_file(file_path, opts \\ []) do
    case File.read(file_path) do
      {:ok, data} ->
        opts = Keyword.put_new(opts, :content_type, guess_content_type(file_path))
        upload_data(data, Path.basename(file_path), opts)

      {:error, reason} ->
        {:error, {:file_error, reason}}
    end
  end

  @doc """
  Uploads binary data. Filename is unused by Blossom (hash-addressed) but kept
  for call-site compatibility.
  """
  def upload_data(data, _filename, opts \\ []) do
    signer = upload_signer_from_opts(opts)
    content_type = Keyword.get(opts, :content_type, "application/octet-stream")
    sha256 = sha256_hex(data)

    server =
      case Keyword.get(opts, :server) do
        nil -> configured_server()
        "" -> configured_server()
        url -> String.trim_trailing(url, "/")
      end

    if is_nil(server) do
      {:error, :no_upload_endpoint}
    else
      put_blob(server, data, sha256, content_type, signer)
    end
  end

  @doc """
  Uploads a post's featured image to the configured Blossom server if needed.
  """
  @spec ensure_post_image(Rss2Nostr.Posts.Post.t(), Signer.signer() | binary()) ::
          {:ok, Rss2Nostr.Posts.Post.t()} | {:error, term()}
  def ensure_post_image(post, signer), do: ensure_post_images(post, signer)

  @doc """
  Uploads the featured image and every referenced article image, then
  rewrites Markdown URLs to the Blossom copies.

  `signer` is `{:private_key, key}`, `{:bunker, url}`, or a raw key binary.
  Does not change post status. Returns `{:error, reason}` when any image
  is still missing so the caller can leave the post pending.
  """
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
          message = "Blossom upload failed: #{format_error(reason)}"
          Logger.warning("[Blossom] #{message} (post #{post.id})")
          _ = Posts.update_post(post, %{last_error: message})
          {:error, reason}

        {_pending, []} ->
          {:error, :images_pending}
      end
    end)
  end

  @doc """
  Marks already-hosted image records as uploaded without contacting Blossom.
  """
  @spec stamp_hosted_images(Rss2Nostr.Posts.Post.t()) ::
          {Rss2Nostr.Posts.Post.t(), %{String.t() => String.t()}}
  def stamp_hosted_images(post) do
    post = Posts.preload_images(post)

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

          already_hosted?(image.original_url) or MapSet.member?(uploaded_urls, image.original_url) ->
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
      if present?(post.image) and already_hosted?(post.image) do
        Map.put_new(mapping, post.image, post.image)
      else
        mapping
      end

    {:ok, post} = apply_image_mapping(post, mapping)
    {Posts.preload_images(post), mapping}
  end

  @doc """
  True when the featured image or any article image still needs a Blossom URL.
  """
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
      case upload_from_url(image.original_url, signer: open_signer) do
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
    present?(image.uploaded_url) or already_hosted?(image.original_url) or
      MapSet.member?(uploaded_urls, image.original_url)
  end

  defp mapping_or_hosted(url, images) do
    cond do
      already_hosted?(url) ->
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
    NIP92.stored_attrs(
      %{
        url: image.original_url,
        sha256: image.sha256,
        size: image.file_size,
        type: image.mime_type,
        nip94: []
      },
      alt: image.alt_text
    )
    |> Map.merge(%{
      imeta:
        case image.imeta do
          pairs when is_list(pairs) and pairs != [] -> pairs
          _ -> NIP92.pairs_from_url(image.original_url, alt: image.alt_text, mime: image.mime_type)
        end
    })
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

  @doc """
  Downloads an image from a URL and uploads it to Blossom.
  """
  def upload_from_url(image_url, opts \\ []) do
    image_url
    |> ImageExtractor.download_urls()
    |> Enum.reduce_while({:error, {:download_failed, :no_url}}, fn url, _acc ->
      kind = if ImageExtractor.audio_url?(url), do: "audio", else: "image"
      Logger.info("Downloading #{kind} from #{url}")

      case HTTP.get(url, receive_timeout: download_timeout(url), retry: false) do
        {:ok, %{status: 200, body: data, headers: headers}} ->
          content_type = content_type_for(url, headers)
          filename = extract_filename(url, content_type)
          opts = Keyword.put_new(opts, :content_type, content_type)
          {:halt, upload_data(data, filename, opts)}

        {:ok, %{status: code}} ->
          {:cont, {:error, {:download_failed, code}}}

        {:error, exception} ->
          {:cont, {:error, {:download_failed, exception}}}
      end
    end)
  end

  @doc """
  Parses a BUD-02 blob descriptor JSON object or encoded string.
  """
  @spec parse_descriptor(map() | String.t()) :: {:ok, upload_result()} | {:error, atom()}
  def parse_descriptor(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, json} -> parse_descriptor(json)
      {:error, _} -> {:error, :invalid_response}
    end
  end

  def parse_descriptor(%{"url" => url} = json) when is_binary(url) and url != "" do
    size =
      case json["size"] do
        n when is_integer(n) -> n
        n when is_binary(n) -> String.to_integer(n)
        _ -> nil
      end

    {:ok,
     %{
       url: url,
       sha256: json["sha256"],
       size: size,
       type: json["type"],
       nip94: json["nip94"] || [],
       dimensions: nil
     }}
  end

  def parse_descriptor(_), do: {:error, :unexpected_response}

  defp put_blob(server, data, sha256, content_type, signer) do
    with {:ok, auth_header} <- create_auth(signer, sha256, server) do
      url = upload_url(server)
      Logger.info("Uploading blob #{String.slice(sha256, 0, 12)}… to #{url}")

      case HTTP.put(url,
             headers: [
               {"authorization", auth_header},
               {"content-type", normalize_content_type(content_type)},
               {"x-sha-256", sha256}
             ],
             body: data,
             receive_timeout: upload_timeout(content_type),
             retry: false
           ) do
        {:ok, %{status: code, body: body}} when code in [200, 201] ->
          parse_descriptor(body)

        {:ok, %{status: code, body: body}} ->
          Logger.error("Blossom upload failed with status #{code}: #{body}")
          {:error, {:upload_failed, code, body}}

        {:error, exception} ->
          {:error, {:upload_failed, exception}}
      end
    end
  end

  defp create_auth(signer, sha256, server_url) do
    with {:ok, pubkey_hex} <- Signer.pubkey_hex(normalize_signer(signer)) do
      now = System.os_time(:second) - 1
      expiration = now + @auth_ttl_seconds
      host = server_host(server_url)

      tags = [
        ["t", "upload"],
        ["expiration", Integer.to_string(expiration)],
        ["x", sha256]
      ]

      tags =
        if host do
          tags ++ [["server", host]]
        else
          tags
        end

      event = %{
        pubkey: pubkey_hex,
        created_at: now,
        kind: @kind_auth,
        tags: tags,
        content: "Upload Blob"
      }

      case Signer.sign_event(normalize_signer(signer), event) do
        {:ok, signed} -> {:ok, authorization_header(signed)}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp upload_signer_from_opts(opts) do
    cond do
      Keyword.has_key?(opts, :signer) -> normalize_signer(Keyword.fetch!(opts, :signer))
      Keyword.has_key?(opts, :private_key) -> {:private_key, Keyword.fetch!(opts, :private_key)}
      true -> raise KeyError, key: :signer, term: opts
    end
  end

  defp normalize_signer({:private_key, key}), do: {:private_key, key}
  defp normalize_signer({:bunker, value}), do: {:bunker, value}
  defp normalize_signer(key) when is_binary(key), do: {:private_key, key}

  defp server_host(nil), do: nil

  defp server_host(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) and host != "" -> String.downcase(host)
      _ -> nil
    end
  end

  defp format_error(:no_upload_endpoint), do: "NOSTR_UPLOAD_ENDPOINT is not set"

  defp format_error({:upload_failed, code, body}) when is_binary(body) do
    "HTTP #{code}: #{String.slice(body, 0, 200)}"
  end

  defp format_error({:download_failed, code}) when is_integer(code), do: "download HTTP #{code}"
  defp format_error({:download_failed, other}), do: "download failed: #{inspect(other)}"
  defp format_error(reason), do: inspect(reason)

  defp normalize_content_type(value) when is_binary(value) do
    value
    |> String.split(";", parts: 2)
    |> List.first()
    |> String.trim()
    |> case do
      "" -> "application/octet-stream"
      type -> type
    end
  end

  defp normalize_content_type(_), do: "application/octet-stream"

  defp sha256_hex(data) do
    :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)
  end

  defp content_type_for(url, headers) do
    header =
      headers
      |> HTTP.header("content-type")
      |> normalize_content_type()

    cond do
      header not in ["application/octet-stream", "binary/octet-stream"] -> header
      true -> guess_content_type(url)
    end
  end

  defp download_timeout(url) do
    if ImageExtractor.audio_url?(url), do: @audio_download_ms, else: @image_download_ms
  end

  defp upload_timeout(content_type) when is_binary(content_type) do
    if String.starts_with?(content_type, "audio/"), do: @audio_upload_ms, else: @image_upload_ms
  end

  defp upload_timeout(_), do: @image_upload_ms

  defp guess_content_type(file_path) do
    path =
      case URI.parse(file_path) do
        %URI{path: path} when is_binary(path) and path != "" -> path
        _ -> file_path
      end

    case Path.extname(path) |> String.downcase() do
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".png" -> "image/png"
      ".gif" -> "image/gif"
      ".webp" -> "image/webp"
      ".svg" -> "image/svg+xml"
      ".mp3" -> "audio/mpeg"
      ".m4a" -> "audio/mp4"
      ".aac" -> "audio/aac"
      ".ogg" -> "audio/ogg"
      ".opus" -> "audio/opus"
      ".wav" -> "audio/wav"
      _ -> "application/octet-stream"
    end
  end

  defp extract_filename(url, content_type) do
    path = URI.parse(url).path || ""
    basename = Path.basename(path)

    if basename != "" and String.contains?(basename, ".") do
      basename
    else
      ext =
        case content_type do
          "image/jpeg" -> ".jpg"
          "image/png" -> ".png"
          "image/gif" -> ".gif"
          "image/webp" -> ".webp"
          "audio/mpeg" -> ".mp3"
          "audio/mp4" -> ".m4a"
          "audio/aac" -> ".aac"
          "audio/ogg" -> ".ogg"
          "audio/opus" -> ".opus"
          "audio/wav" -> ".wav"
          _ -> ".bin"
        end

      prefix = if String.starts_with?(content_type, "audio/"), do: "audio", else: "image"
      "#{prefix}_#{System.system_time(:second)}#{ext}"
    end
  end
end
