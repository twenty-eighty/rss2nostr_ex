defmodule Rss2Nostr.Processing.ImageExtractor do
  @moduledoc """
  Extracts images, audio, and video file links from Markdown and stores
  them for later Blossom upload.
  """

  alias Rss2Nostr.Posts
  alias Rss2Nostr.Posts.Post
  alias Rss2Nostr.Processing.ImageExtractor.{Media, Urls}

  @type image_info :: %{url: String.t(), alt: String.t(), caption: String.t() | nil}

  @doc """
  Extracts all images from a post's content and featured image,
  creating ArticleImage records for each.
  """
  @spec extract_and_store(Post.t()) :: {:ok, Post.t(), non_neg_integer()}
  def extract_and_store(%Post{} = post) do
    post = post |> repair_post_urls() |> Posts.preload_images()
    known = known_image_urls(post)

    images =
      extract_images(post.content, post.image) ++
        extract_audio(post.content) ++ extract_video(post.content)

    created =
      Enum.reduce(images, 0, fn image, count ->
        if known_url?(known, image.url) do
          count
        else
          attrs = %{
            post_id: post.id,
            original_url: image.url,
            alt_text: image.alt,
            caption: image.caption
          }

          case Posts.create_image(attrs) do
            {:ok, _} -> count + 1
            {:error, _} -> count
          end
        end
      end)

    post = prune_unreferenced_images(post, images)

    {:ok, Posts.preload_images(post), created}
  end

  @doc """
  Extracts image information from Markdown content.
  Returns a list of %{url: ..., alt: ..., caption: ...}
  """
  @spec extract_images(String.t() | nil, String.t() | nil) :: [image_info()]
  def extract_images(content, featured_image \\ nil) do
    content_images = extract_markdown_images(content || "")

    all_images =
      if featured_image && featured_image != "" do
        featured = %{url: featured_image, alt: "", caption: nil}
        urls = Enum.map(content_images, & &1.url)

        if featured_image in urls do
          content_images
        else
          [featured | content_images]
        end
      else
        content_images
      end

    all_images
    |> Enum.map(fn image -> %{image | url: display_url(image.url)} end)
    |> Enum.uniq_by(& &1.url)
    |> Enum.filter(&Urls.valid?(&1.url))
  end

  @doc """
  Extracts images from Markdown using regex patterns.
  """
  @spec extract_markdown_images(String.t() | any()) :: [image_info()]
  def extract_markdown_images(markdown) when is_binary(markdown) do
    pattern = ~r/!\[([^\]]*)\]\(([^)\s]+)(?:\s+"([^"]*)")?\)/

    Regex.scan(pattern, markdown)
    |> Enum.map(fn
      [_full, alt, url, title] ->
        %{url: String.trim(url), alt: String.trim(alt), caption: title}

      [_full, alt, url] ->
        %{url: String.trim(url), alt: String.trim(alt), caption: nil}
    end)
  end

  def extract_markdown_images(_), do: []

  @spec extract_audio(String.t() | nil) :: [image_info()]
  def extract_audio(content), do: Media.extract_audio(content)

  @spec extract_markdown_audio(String.t() | any()) :: [image_info()]
  def extract_markdown_audio(markdown), do: Media.extract_markdown_audio(markdown)

  @spec audio_url?(String.t() | nil) :: boolean()
  def audio_url?(url), do: Media.audio_url?(url)

  @spec extract_video(String.t() | nil) :: [image_info()]
  def extract_video(content), do: Media.extract_video(content)

  @spec video_url?(String.t() | nil) :: boolean()
  def video_url?(url), do: Media.video_url?(url)

  @spec parse_media_caption(String.t() | nil) :: %{
          duration: integer() | nil,
          size: integer() | nil
        }
  def parse_media_caption(caption), do: Media.parse_media_caption(caption)

  @spec clock_to_seconds(String.t() | nil) :: integer() | nil
  def clock_to_seconds(value), do: Media.clock_to_seconds(value)

  @spec replace_image_urls(String.t() | any(), map()) :: String.t()
  def replace_image_urls(content, url_mapping) when is_binary(content) and is_map(url_mapping) do
    Enum.reduce(url_mapping, content, fn {original_url, new_url}, acc ->
      String.replace(acc, original_url, new_url)
    end)
  end

  def replace_image_urls(content, _), do: content

  @spec normalize_url(String.t() | nil) :: String.t()
  def normalize_url(url), do: Urls.normalize(url)

  @spec display_url(String.t() | nil) :: String.t()
  def display_url(url), do: Urls.display(url)

  @spec download_urls(String.t() | nil) :: [String.t()]
  def download_urls(url), do: Urls.download_urls(url)

  @spec known_image_urls(Post.t()) :: MapSet.t(String.t())
  defp known_image_urls(post) do
    (post.images || [])
    |> Enum.flat_map(fn image ->
      [image.original_url, image.uploaded_url, normalize_url(image.original_url)]
    end)
    |> Enum.filter(&(is_binary(&1) and String.trim(&1) != ""))
    |> MapSet.new()
  end

  @spec known_url?(MapSet.t(String.t()), String.t()) :: boolean()
  defp known_url?(known, url) do
    MapSet.member?(known, url) or MapSet.member?(known, normalize_url(url))
  end

  @spec repair_post_urls(Post.t()) :: Post.t()
  defp repair_post_urls(%Post{} = post) do
    content = repair_content(post.content)
    image = normalize_optional_url(post.image)

    if content == post.content and image == post.image do
      post
    else
      {:ok, post} = Posts.update_post(post, %{content: content, image: image})
      post
    end
  end

  @spec repair_content(String.t() | nil) :: String.t() | nil
  defp repair_content(content) when is_binary(content) do
    content
    |> strip_tracking_pixel_images()
    |> then(fn repaired ->
      Regex.replace(~r/!\[([^\]]*)\]\(([^)\s]+)((?:\s+"[^"]*")?)\)/, repaired, fn _full,
                                                                                  alt,
                                                                                  url,
                                                                                  rest ->
        "![#{alt}](#{display_url(url)}#{rest})"
      end)
    end)
  end

  defp repair_content(content), do: content

  @spec strip_tracking_pixel_images(String.t()) :: String.t()
  defp strip_tracking_pixel_images(content) do
    Regex.replace(
      ~r/!?\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)/,
      content,
      fn full, _alt, url ->
        if Urls.tracking_pixel?(url), do: "", else: full
      end
    )
  end

  @spec normalize_optional_url(String.t() | nil) :: String.t() | nil
  defp normalize_optional_url(url) when is_binary(url) and url != "" do
    cond do
      Urls.tracking_pixel?(url) ->
        nil

      true ->
        case display_url(url) do
          "" -> url
          displayed -> displayed
        end
    end
  end

  defp normalize_optional_url(url), do: url

  @spec prune_unreferenced_images(Post.t(), [image_info()]) :: Post.t()
  defp prune_unreferenced_images(post, wanted) do
    wanted_urls = referenced_url_set(wanted)

    (post.images || [])
    |> Enum.filter(fn image ->
      Urls.tracking_pixel?(image.original_url) or not image_referenced?(image, wanted_urls)
    end)
    |> Enum.each(&Posts.delete_image/1)

    post
  end

  @spec referenced_url_set([image_info()]) :: MapSet.t(String.t())
  defp referenced_url_set(images) do
    images
    |> Enum.flat_map(fn %{url: url} -> url_variants(url) end)
    |> Enum.filter(&(is_binary(&1) and String.trim(&1) != ""))
    |> MapSet.new()
  end

  @spec image_referenced?(map(), MapSet.t(String.t())) :: boolean()
  defp image_referenced?(image, wanted) do
    [image.original_url, image.uploaded_url]
    |> Enum.flat_map(&url_variants/1)
    |> Enum.any?(&MapSet.member?(wanted, &1))
  end

  @spec url_variants(String.t() | nil) :: [String.t()]
  defp url_variants(url) when is_binary(url) and url != "" do
    [url, Urls.normalize(url), Urls.display(url) | Urls.download_urls(url)]
  end

  defp url_variants(_), do: []
end
