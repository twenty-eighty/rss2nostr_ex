defmodule Rss2Nostr.Processing.Processor do
  @moduledoc """
  Orchestrates the processing of imported posts:
  1. Converts HTML content to Markdown
  2. Extracts images and audio file links
  3. Uploads featured and referenced images and audio to Blossom
  4. Marks processed only when media is done
  """

  require Logger

  alias Rss2Nostr.Nostr.{Blossom, Signer}
  alias Rss2Nostr.Posts
  alias Rss2Nostr.Posts.Post
  alias Rss2Nostr.Processing.{Composer, HtmlToMarkdown, ImageExtractor}

  @type process_result :: %{
          processed: non_neg_integer(),
          errors: non_neg_integer(),
          skipped: non_neg_integer()
        }

  @doc """
  Processes new posts and posts waiting on image uploads.
  """
  @spec process_new_posts(keyword()) :: process_result()
  def process_new_posts(opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)

    Posts.list_processable_posts(limit: limit)
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
      end
    end)
  end

  @doc """
  Processes a single post by ID.
  """
  @spec process_post_by_id(integer()) :: {:ok, Post.t()} | {:error, any()}
  def process_post_by_id(post_id) do
    case Posts.get_post(post_id) do
      nil -> {:error, :not_found}
      post -> process_post(post)
    end
  end

  @doc """
  Processes a single post:
  1. Convert HTML to Markdown (unless only images remain)
  2. Extract images and audio file links
  3. Upload featured and referenced images and audio
  4. Mark as processed only when media is done; otherwise pending images
  """
  @spec process_post(Post.t()) :: {:ok, Post.t()} | {:error, any()}
  def process_post(%Post{} = post) do
    Logger.info("Processing post: #{post.title}")

    try do
      cond do
        post.status == Post.status_pending_images() and present?(post.content) ->
          ensure_images(post)

        is_nil(post.source_html) or post.source_html == "" ->
          {:ok, post} = Posts.mark_processing(post)
          Logger.warning("Post #{post.id} has no source HTML, skipping conversion")
          ensure_images(post)

        true ->
          {:ok, post} = Posts.mark_processing(post)
          compose_and_store(post)
      end
    rescue
      e ->
        Logger.error("Error processing post #{post.id}: #{inspect(e)}")
        Posts.mark_error(post, inspect(e))
        {:error, e}
    end
  end

  @doc """
  Uploads remaining images and marks the post processed, or pending images.
  """
  @spec ensure_images(Post.t()) :: {:ok, Post.t()}
  def ensure_images(%Post{} = post) do
    {:ok, post, _count} = ImageExtractor.extract_and_store(post)
    post = post |> Posts.preload_source() |> Posts.preload_images()
    {post, _mapping} = Blossom.stamp_hosted_images(post)

    cond do
      not Blossom.pending_images?(post) ->
        finish_images(post)

      true ->
        case Signer.upload_signer(post.source) do
          {:ok, signer} ->
            case Blossom.ensure_post_images(post, signer) do
              {:ok, post} ->
                finish_images(post)

              {:error, reason} ->
                pend_images(post, format_image_error(reason))
            end

          {:error, reason} ->
            pend_images(post, format_image_error(reason))
        end
    end
  end

  @spec compose_and_store(Post.t()) :: {:ok, Post.t()} | {:error, any()}
  defp compose_and_store(%Post{} = post) do
    post = Posts.preload_source(post)
    composed = Composer.compose(post.source_html, compose_opts_for(post))
    store_composed(post, composed)
  end

  @spec compose_opts_for(Post.t()) :: Composer.compose_opts()
  defp compose_opts_for(%Post{} = post) do
    source = post.source

    source
    |> Composer.opts_from_source()
    |> Map.put(:url, post.source_url || feed_url(source))
    |> Map.put(:image, post.image)
    |> Map.put(:title, post.title)
    |> Map.put(:summary, post.summary)
    |> Map.put(:language, post.language || (source && source.language))
    |> Map.put(:fetch_page_image, true)
  end

  @spec feed_url(map() | term()) :: String.t() | nil
  defp feed_url(%{url: url}), do: url
  defp feed_url(_), do: nil

  @spec store_composed(Post.t(), map()) :: {:ok, Post.t()} | {:error, any()}
  defp store_composed(%Post{} = post, composed) do
    {:ok, post} =
      Posts.update_post(post, %{
        content: composed.markdown,
        summary:
          HtmlToMarkdown.plain_summary(post.summary) || composed.summary ||
            generate_summary(composed.markdown),
        image: post.image || composed.image
      })

    ensure_images(post)
  end

  @doc """
  Marks a pending-images post processed when every image already has a
  Blossom URL. Used when opening a post so a leftover status/error is not shown.
  """
  @spec finish_if_images_ready(Post.t()) :: Post.t()
  def finish_if_images_ready(%Post{} = post) do
    {:ok, post, _count} = ImageExtractor.extract_and_store(post)
    post = Posts.preload_images(post)

    cond do
      Blossom.pending_images?(post) ->
        {:ok, post} = ensure_images(post)
        post

      post.status == Post.status_pending_images() ->
        {:ok, post} = finish_images(post)
        post

      true ->
        post
    end
  end

  @spec finish_images(Post.t()) :: {:ok, Post.t()}
  defp finish_images(post) do
    {:ok, post} = Posts.enter_staging(post)
    Logger.info("Staging: #{post.title}")
    {:ok, post}
  end

  @spec pend_images(Post.t(), String.t()) :: {:ok, Post.t()}
  defp pend_images(post, "Images still need uploading") do
    {:ok, post} =
      Posts.update_post(post, %{status: Post.status_pending_images(), last_error: nil})

    Logger.info("Pending images: #{post.title}")
    {:ok, post}
  end

  defp pend_images(post, message) do
    {:ok, post} = Posts.mark_pending_images(post, message)
    Logger.info("Pending images: #{post.title} (#{message})")
    {:ok, post}
  end

  @spec format_image_error(atom() | String.t() | term()) :: String.t()
  defp format_image_error(:no_upload_endpoint), do: "NOSTR_UPLOAD_ENDPOINT is not set"

  defp format_image_error(:no_app_private_key),
    do: "NOSTR_NSEC is not set (needed to upload draft images)"

  defp format_image_error(:no_source_pubkey),
    do: "Draft source needs an intended author pubkey to upload images with the app key"

  defp format_image_error(:no_source_signer),
    do: "Source has no nsec or bunker URL for image upload"

  defp format_image_error(:images_pending), do: "Images still need uploading"
  defp format_image_error(:no_source), do: "Post has no source for image upload"
  defp format_image_error(reason) when is_binary(reason), do: reason
  defp format_image_error(reason), do: "Blossom upload failed: #{inspect(reason)}"

  @spec present?(term()) :: boolean()
  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: false

  @doc """
  Generates a summary from markdown content.
  Takes the first paragraph, truncated to ~200 characters.
  """
  @spec generate_summary(String.t() | nil) :: String.t() | nil
  def generate_summary(nil), do: nil
  def generate_summary(""), do: nil

  def generate_summary(markdown) do
    markdown
    |> String.split("\n\n")
    |> Enum.find(&summary_paragraph?/1)
    |> case do
      nil ->
        nil

      paragraph ->
        paragraph
        |> String.trim()
        |> truncate_text(200)
    end
  end

  @spec summary_paragraph?(String.t()) :: boolean()
  defp summary_paragraph?(para) do
    trimmed = String.trim(para)

    trimmed != "" and
      not String.starts_with?(trimmed, "#") and
      not markdown_media_only?(trimmed)
  end

  @spec markdown_media_only?(String.t()) :: boolean()
  defp markdown_media_only?(text) do
    Regex.match?(~r/\A!?(\[[^\]]*\]\([^)]+\)\s*)+\z/, text)
  end

  @spec truncate_text(String.t(), pos_integer()) :: String.t()
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
  @spec reprocess_post(Post.t()) :: {:ok, Post.t()} | {:error, any()}
  def reprocess_post(%Post{} = post) do
    attrs = %{status: Post.status_new(), last_error: nil}

    attrs =
      if post.status == Post.status_published(), do: Map.put(attrs, :staged_at, nil), else: attrs

    {:ok, post} = Posts.update_post(post, attrs)
    process_post(post)
  end

  @spec reprocess_post_by_id(integer()) :: {:ok, Post.t()} | {:error, any()}
  def reprocess_post_by_id(post_id) do
    case Posts.get_post(post_id) do
      nil -> {:error, :not_found}
      post -> reprocess_post(post)
    end
  end
end
