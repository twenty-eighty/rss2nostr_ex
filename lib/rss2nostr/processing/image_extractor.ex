defmodule Rss2Nostr.Processing.ImageExtractor do
  @moduledoc """
  Extracts images, audio, and video file links from Markdown and stores
  them for later Blossom upload.
  """

  require Logger

  alias Rss2Nostr.Posts
  alias Rss2Nostr.Posts.Post

  @audio_ext ~w(mp3 m4a aac ogg opus wav)
  @video_ext ~w(mp4 m4v webm mov mkv)

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

    {:ok, Posts.preload_images(post), created}
  end

  defp known_image_urls(post) do
    (post.images || [])
    |> Enum.flat_map(fn image ->
      [image.original_url, image.uploaded_url, normalize_url(image.original_url)]
    end)
    |> Enum.filter(&(is_binary(&1) and String.trim(&1) != ""))
    |> MapSet.new()
  end

  defp known_url?(known, url) do
    MapSet.member?(known, url) or MapSet.member?(known, normalize_url(url))
  end

  @doc """
  Extracts image information from Markdown content.
  Returns a list of %{url: ..., alt: ..., caption: ...}
  """
  @spec extract_images(String.t() | nil, String.t() | nil) :: [image_info()]
  def extract_images(content, featured_image \\ nil) do
    content_images = extract_markdown_images(content || "")

    # Add featured image if not already in content
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
    |> Enum.filter(&valid_image_url?(&1.url))
  end

  @doc """
  Extracts images from Markdown using regex patterns.
  Handles both simple and titled image syntax:
  - ![alt](url)
  - ![alt](url "title")
  """
  @spec extract_markdown_images(String.t() | any()) :: [image_info()]
  def extract_markdown_images(markdown) when is_binary(markdown) do
    # Pattern for markdown images: ![alt](url) or ![alt](url "title")
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

  @doc """
  Audio file URLs from Markdown links such as `[Audio](https://…/episode.mp3)`.
  Image syntax (`![alt](url)`) is ignored.
  """
  @spec extract_audio(String.t() | nil) :: [image_info()]
  def extract_audio(content) when is_binary(content) do
    content
    |> extract_markdown_audio()
    |> Enum.map(fn item -> %{item | url: normalize_url(item.url)} end)
    |> Enum.uniq_by(& &1.url)
    |> Enum.filter(&valid_image_url?(&1.url))
  end

  def extract_audio(_), do: []

  @spec extract_markdown_audio(String.t() | any()) :: [image_info()]
  def extract_markdown_audio(markdown) when is_binary(markdown) do
    markdown
    |> extract_markdown_links()
    |> Enum.filter(&audio_url?(&1.url))
  end

  def extract_markdown_audio(_), do: []

  defp extract_markdown_links(markdown) when is_binary(markdown) do
    pattern = ~r/(?<!!)\[([^\]]*)\]\(([^)\s]+)(?:\s+"([^"]*)")?\)/

    Regex.scan(pattern, markdown)
    |> Enum.map(fn
      [_full, alt, url, title] ->
        %{url: String.trim(url), alt: String.trim(alt), caption: title}

      [_full, alt, url] ->
        %{url: String.trim(url), alt: String.trim(alt), caption: nil}
    end)
  end

  @doc """
  True when `url` points at an audio file (by path extension).
  """
  @spec audio_url?(String.t() | nil) :: boolean()
  def audio_url?(url) when is_binary(url) do
    path_ext(url) in @audio_ext
  end

  def audio_url?(_), do: false

  @doc """
  Video file URLs from Markdown links such as `[Video](https://…/episode.mp4)`.
  """
  @spec extract_video(String.t() | nil) :: [image_info()]
  def extract_video(content) when is_binary(content) do
    content
    |> extract_markdown_links()
    |> Enum.map(fn item -> %{item | url: normalize_url(item.url)} end)
    |> Enum.uniq_by(& &1.url)
    |> Enum.filter(&video_url?(&1.url))
    |> Enum.filter(&valid_image_url?(&1.url))
  end

  def extract_video(_), do: []

  @doc """
  True when `url` points at a video file (by path extension).
  """
  @spec video_url?(String.t() | nil) :: boolean()
  def video_url?(url) when is_binary(url) do
    path_ext(url) in @video_ext
  end

  def video_url?(_), do: false

  @doc """
  Duration and optional byte size from a markdown title / RSS caption.

  Accepts `23:43`, `01:15:39`, a second count, and an optional enclosure
  length: `"23:43 66928694"`.
  """
  @spec parse_media_caption(String.t() | nil) :: %{duration: integer() | nil, size: integer() | nil}
  def parse_media_caption(caption) when is_binary(caption) do
    tokens = String.split(caption, ~r/\s+/, trim: true)
    {clocks, rest} = Enum.split_with(tokens, &String.contains?(&1, ":"))

    duration =
      clocks
      |> List.first()
      |> clock_to_seconds()

    integers =
      Enum.flat_map(rest, fn token ->
        case Integer.parse(token) do
          {n, ""} when n > 0 -> [n]
          _ -> []
        end
      end)

    {sizes, seconds} = Enum.split_with(integers, &(&1 >= 10_000))

    %{
      duration: duration || List.first(seconds),
      size: List.first(sizes)
    }
  end

  def parse_media_caption(_), do: %{duration: nil, size: nil}

  @doc """
  Parses `HH:MM:SS`, `MM:SS`, or a raw second count from RSS/iTunes.
  """
  @spec clock_to_seconds(String.t() | nil) :: integer() | nil
  def clock_to_seconds(value) when is_binary(value) do
    trimmed = String.trim(value)

    cond do
      trimmed == "" ->
        nil

      String.match?(trimmed, ~r/^\d+$/) ->
        String.to_integer(trimmed)

      String.match?(trimmed, ~r/^\d+:\d{1,2}(:\d{1,2})?$/) ->
        trimmed
        |> String.split(":")
        |> Enum.map(&String.to_integer/1)
        |> Enum.reduce(0, fn part, acc -> acc * 60 + part end)

      true ->
        parse_media_caption(trimmed).duration
    end
  end

  def clock_to_seconds(_), do: nil

  @doc """
  Replaces image URLs in Markdown content with new URLs.
  Used after images have been uploaded to replace original URLs with uploaded URLs.
  """
  @spec replace_image_urls(String.t() | any(), map()) :: String.t()
  def replace_image_urls(content, url_mapping) when is_binary(content) and is_map(url_mapping) do
    Enum.reduce(url_mapping, content, fn {original_url, new_url}, acc ->
      String.replace(acc, original_url, new_url)
    end)
  end

  def replace_image_urls(content, _), do: content

  @doc """
  Turns CDN fetch wrappers and encoded inner URLs into a fetchable http(s) URL.

  Substack/Cloudinary often look like:
  `…/image/fetch/w_1200,c_limit,fl_progressive:steep/https%3A%2F%2F…`
  After a broken srcset split only the `fl_progressive:steep/https%3A%2F%2F…`
  fragment remains. Both resolve to the original image URL.
  """
  @spec normalize_url(String.t() | nil) :: String.t()
  def normalize_url(url) when is_binary(url) do
    url
    |> String.trim()
    |> prefix_protocol_relative()
    |> unwrap_encoded_fetch()
  end

  def normalize_url(nil), do: ""

  @heic_ext ~w(heic heif)
  @substack_cdn_prefix "https://substackcdn.com/image/fetch/f_auto,q_auto:good,fl_progressive:steep/"
  # No commas: Markdown image destinations split on `,`.
  @substack_display_prefix "https://substackcdn.com/image/fetch/f_jpg/"

  @doc """
  URL suitable for Markdown and browsers.

  HEIC/HEIF files on Substack S3 do not render in most clients. Keep
  (or restore) the CDN `f_auto` fetch wrapper so they are served as
  JPEG/WebP.
  """
  @spec display_url(String.t() | nil) :: String.t()
  def display_url(url) when is_binary(url) do
    origin = normalize_url(url)

    cond do
      origin == "" ->
        url

      heic_url?(origin) ->
        substack_display_url(origin) || url

      true ->
        origin
    end
  end

  def display_url(nil), do: ""

  @doc """
  URLs to try when downloading `url`. The stored URL is first; if it is a
  Substack origin that AWS often 403s, the Substack CDN fetch wrapper is next.
  """
  @spec download_urls(String.t() | nil) :: [String.t()]
  def download_urls(url) when is_binary(url) do
    url = String.trim(url)
    origin = normalize_url(url)

    [url, origin, substack_cdn_url(origin)]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.uniq()
  end

  def download_urls(_), do: []

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

  defp repair_content(content) when is_binary(content) do
    Regex.replace(~r/!\[([^\]]*)\]\(([^)\s]+)((?:\s+"[^"]*")?)\)/, content, fn _full, alt, url, rest ->
      "![#{alt}](#{display_url(url)}#{rest})"
    end)
  end

  defp repair_content(content), do: content

  defp normalize_optional_url(url) when is_binary(url) and url != "" do
    case display_url(url) do
      "" -> url
      displayed -> displayed
    end
  end

  defp normalize_optional_url(url), do: url

  defp prefix_protocol_relative("//" <> rest), do: "https://" <> rest
  defp prefix_protocol_relative(url), do: url

  defp substack_cdn_url(origin) when is_binary(origin) and origin != "" do
    if substack_origin?(origin) and not substack_cdn?(origin) do
      @substack_cdn_prefix <> URI.encode(origin, &URI.char_unreserved?/1)
    end
  end

  defp substack_cdn_url(_), do: nil

  defp substack_display_url(origin) when is_binary(origin) and origin != "" do
    if substack_origin?(origin) and not substack_cdn?(origin) do
      @substack_display_prefix <> URI.encode(origin, &URI.char_unreserved?/1)
    end
  end

  defp substack_display_url(_), do: nil

  defp substack_cdn?(url) do
    host = url_host(url)
    host == "substackcdn.com" or String.ends_with?(host, ".substackcdn.com")
  end

  defp substack_origin?(url) do
    host = url_host(url)

    String.contains?(host, "substack") or
      (String.contains?(host, "amazonaws.com") and String.contains?(url, "/public/images/"))
  end

  defp url_host(url) do
    url |> URI.parse() |> Map.get(:host) |> to_string() |> String.downcase()
  rescue
    _ -> ""
  end

  defp unwrap_encoded_fetch(url) do
    case Regex.run(~r/(https?%3A%2F%2F[^\s)]+)/i, url) do
      [_, encoded] ->
        decoded = URI.decode(encoded)
        if valid_image_url?(decoded), do: decoded, else: url

      _ ->
        url
    end
  end

  defp heic_url?(url), do: path_ext(url) in @heic_ext

  defp path_ext(url) when is_binary(url) do
    url
    |> String.trim()
    |> URI.parse()
    |> Map.get(:path, "")
    |> to_string()
    |> Path.extname()
    |> String.downcase()
    |> String.trim_leading(".")
  end

  defp valid_image_url?(nil), do: false
  defp valid_image_url?(""), do: false

  defp valid_image_url?(url) do
    uri = URI.parse(url)
    uri.scheme in ["http", "https"] and is_binary(uri.host) and uri.host != ""
  rescue
    e ->
      Logger.debug("Invalid image URL #{inspect(url)}: #{inspect(e)}")
      false
  end
end
