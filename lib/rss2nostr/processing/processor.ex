defmodule Rss2Nostr.Processing.Processor do
  @moduledoc """
  Orchestrates the processing of imported posts:
  1. Converts HTML content to Markdown
  2. Extracts and stores images
  3. Updates post status
  """

  require Logger

  alias Rss2Nostr.Posts
  alias Rss2Nostr.Posts.Post
  alias Rss2Nostr.Processing.{HtmlToMarkdown, ImageExtractor}

  @type process_result :: %{
          processed: non_neg_integer(),
          errors: non_neg_integer(),
          skipped: non_neg_integer()
        }

  @doc """
  Processes all new posts (status = 0).
  """
  @spec process_new_posts(keyword()) :: process_result()
  def process_new_posts(opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)

    Posts.list_new_posts(limit: limit)
    |> process_posts()
  end

  @doc """
  Processes a list of posts.
  """
  @spec process_posts([Post.t()]) :: process_result()
  def process_posts(posts) when is_list(posts) do
    result = %{processed: 0, errors: 0, skipped: 0}

    Enum.reduce(posts, result, fn post, acc ->
      case process_post(post) do
        {:ok, _} -> %{acc | processed: acc.processed + 1}
        {:error, _} -> %{acc | errors: acc.errors + 1}
        :skipped -> %{acc | skipped: acc.skipped + 1}
      end
    end)
  end

  @doc """
  Processes a single post by ID.
  """
  @spec process_post_by_id(integer()) :: {:ok, Post.t()} | {:error, any()} | :skipped
  def process_post_by_id(post_id) do
    case Posts.get_post(post_id) do
      nil -> {:error, :not_found}
      post -> process_post(post)
    end
  end

  @doc """
  Processes a single post:
  1. Mark as processing
  2. Convert HTML to Markdown
  3. Extract images
  4. Update post with content
  5. Mark as processed
  """
  @spec process_post(Post.t()) :: {:ok, Post.t()} | {:error, any()} | :skipped
  def process_post(%Post{} = post) do
    Logger.info("Processing post: #{post.title}")

    # Mark as processing
    {:ok, post} = Posts.mark_processing(post)

    try do
      # Get the source HTML content
      source_html = post.source_html

      if is_nil(source_html) || source_html == "" do
        Logger.warning("Post #{post.id} has no source HTML, skipping conversion")
        {:ok, _post} = Posts.mark_processed(post)
        :skipped
      else
        # Convert HTML to Markdown
        markdown = HtmlToMarkdown.convert(source_html)

        # Generate summary if not present
        summary = post.summary || generate_summary(markdown)

        # Update post with processed content
        {:ok, post} =
          Posts.update_post(post, %{
            content: markdown,
            summary: summary
          })

        # Extract and store images
        {:ok, image_count} = ImageExtractor.extract_and_store(post)
        Logger.debug("Extracted #{image_count} images from post #{post.id}")

        # Mark as processed
        {:ok, post} = Posts.mark_processed(post)

        Logger.info("Processed: #{post.title}")
        {:ok, post}
      end
    rescue
      e ->
        Logger.error("Error processing post #{post.id}: #{inspect(e)}")
        Posts.mark_error(post, inspect(e))
        {:error, e}
    end
  end

  @doc """
  Generates a summary from markdown content.
  Takes the first paragraph, truncated to ~200 characters.
  """
  @spec generate_summary(String.t() | nil) :: String.t() | nil
  def generate_summary(nil), do: nil
  def generate_summary(""), do: nil

  def generate_summary(markdown) do
    # Get first paragraph (non-empty line that's not a heading)
    markdown
    |> String.split("\n\n")
    |> Enum.find(fn para ->
      trimmed = String.trim(para)
      trimmed != "" && !String.starts_with?(trimmed, "#")
    end)
    |> case do
      nil ->
        nil

      paragraph ->
        paragraph
        |> String.trim()
        |> truncate_text(200)
    end
  end

  defp truncate_text(text, max_length) when byte_size(text) <= max_length, do: text

  defp truncate_text(text, max_length) do
    text
    |> String.slice(0, max_length - 3)
    |> String.trim_trailing()
    |> Kernel.<>("...")
  end

  @doc """
  Reprocesses a post (useful for debugging or after fixes).
  Resets status to new and processes again.
  """
  @spec reprocess_post(Post.t()) :: {:ok, Post.t()} | {:error, any()} | :skipped
  def reprocess_post(%Post{} = post) do
    {:ok, post} = Posts.update_post(post, %{status: Post.status_new()})
    process_post(post)
  end

  @spec reprocess_post_by_id(integer()) :: {:ok, Post.t()} | {:error, any()} | :skipped
  def reprocess_post_by_id(post_id) do
    case Posts.get_post(post_id) do
      nil -> {:error, :not_found}
      post -> reprocess_post(post)
    end
  end
end
