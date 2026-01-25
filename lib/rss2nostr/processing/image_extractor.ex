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
  @spec extract_and_store(Post.t()) :: {:ok, non_neg_integer()}
  def extract_and_store(%Post{} = post) do
    images = extract_images(post.content, post.image)

    Enum.each(images, fn image ->
      attrs = %{
        post_id: post.id,
        original_url: image.url,
        alt_text: image.alt,
        caption: image.caption
      }

      case Posts.create_image(attrs) do
        {:ok, _} -> :ok
        # Ignore duplicates
        {:error, _} -> :ok
      end
    end)

    {:ok, length(images)}
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

    # Deduplicate by URL
    all_images
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

  # Check if URL is a valid image URL
  defp valid_image_url?(nil), do: false
  defp valid_image_url?(""), do: false

  defp valid_image_url?(url) do
    uri = URI.parse(url)

    # Must have scheme and host
    has_scheme = uri.scheme in ["http", "https"]
    has_host = uri.host != nil && uri.host != ""

    # Check for common image extensions or assume it's valid
    # URLs without extension might still be images
    is_image =
      String.ends_with?(String.downcase(url), [".jpg", ".jpeg", ".png", ".gif", ".webp", ".svg"]) ||
        String.contains?(url, "/image") ||
        String.contains?(url, "/img") ||
        !String.contains?(url, ".")

    has_scheme && has_host && is_image
  rescue
    e ->
      Logger.debug("Invalid image URL #{inspect(url)}: #{inspect(e)}")
      false
  end
end
