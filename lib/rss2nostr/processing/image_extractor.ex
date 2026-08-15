defmodule Rss2Nostr.Processing.ImageExtractor do
  @moduledoc """
  Extracts images from Markdown content and stores them for later upload.
  """

  require Logger

  alias Rss2Nostr.Posts
  alias Rss2Nostr.Posts.Post

  @type image_info :: %{url: String.t(), alt: String.t(), caption: String.t() | nil}

  @doc """
  Extracts all images from a post's content and featured image,
  creating ArticleImage records for each.
  """
  @spec extract_and_store(Post.t()) :: {:ok, Post.t(), non_neg_integer()}
  def extract_and_store(%Post{} = post) do
    post = post |> repair_post_urls() |> Posts.preload_images()
    known = known_image_urls(post)
    images = extract_images(post.content, post.image)

    created =
      Enum.reduce(images, 0, fn image, count ->
        if MapSet.member?(known, image.url) do
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
    |> Enum.flat_map(fn image -> [image.original_url, image.uploaded_url] end)
    |> Enum.filter(&(is_binary(&1) and String.trim(&1) != ""))
    |> MapSet.new()
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
    |> Enum.map(fn image -> %{image | url: normalize_url(image.url)} end)
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
      "![#{alt}](#{normalize_url(url)}#{rest})"
    end)
  end

  defp repair_content(content), do: content

  defp normalize_optional_url(url) when is_binary(url) and url != "" do
    case normalize_url(url) do
      "" -> url
      normalized -> normalized
    end
  end

  defp normalize_optional_url(url), do: url

  defp prefix_protocol_relative("//" <> rest), do: "https://" <> rest
  defp prefix_protocol_relative(url), do: url

  defp unwrap_encoded_fetch(url) do
    case Regex.run(~r/(https?%3A%2F%2F[^\s)]+)/i, url) do
      [_, encoded] ->
        decoded = URI.decode(encoded)
        if valid_image_url?(decoded), do: decoded, else: url

      _ ->
        url
    end
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
