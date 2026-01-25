defmodule Rss2Nostr.Scheduler.Tasks do
  @moduledoc """
  Task implementations for the scheduler.

  These are the actual operations that run on schedule:
  - import: Fetch articles from all active sources
  - process: Convert new HTML articles to Markdown
  - export: Publish processed articles to Nostr
  """

  require Logger

  alias Rss2Nostr.Sources
  alias Rss2Nostr.Posts
  alias Rss2Nostr.Import.Importer
  alias Rss2Nostr.Processing.Processor
  alias Rss2Nostr.Nostr.{Publisher, NIP96}

  @type import_result ::
          {:ok,
           %{imported: non_neg_integer(), errors: non_neg_integer(), sources: non_neg_integer()}}
  @type process_result :: {:ok, %{processed: non_neg_integer(), errors: non_neg_integer()}}
  @type export_result ::
          {:ok, %{published: non_neg_integer(), errors: non_neg_integer()}} | {:error, atom()}

  @doc """
  Runs the import task: fetches articles from all active sources.

  Returns {:ok, %{imported: count, errors: count}} or {:error, reason}
  """
  @spec run_import(keyword()) :: import_result()
  def run_import(_opts \\ []) do
    Logger.info("[Scheduler] Starting import task")

    sources = Sources.list_active_sources()

    if Enum.empty?(sources) do
      Logger.info("[Scheduler] No active sources to import")
      {:ok, %{imported: 0, errors: 0, sources: 0}}
    else
      results =
        Enum.map(sources, fn source ->
          Logger.debug("[Scheduler] Importing from #{source.name}")
          # Importer.import_from_source returns a map with :imported, :skipped, :errors keys
          Importer.import_from_source(source)
        end)

      imported = Enum.sum(for %{imported: count} <- results, do: count)
      errors = Enum.sum(for %{errors: errs} <- results, do: length(errs))

      Logger.info(
        "[Scheduler] Import complete: #{imported} articles from #{length(sources)} sources"
      )

      {:ok, %{imported: imported, errors: errors, sources: length(sources)}}
    end
  end

  @doc """
  Runs the process task: converts new HTML articles to Markdown.

  Options:
  - :limit - Maximum number of posts to process (default: 50)

  Returns {:ok, %{processed: count, errors: count}} or {:error, reason}
  """
  @spec run_process(keyword()) :: process_result()
  def run_process(opts \\ []) do
    Logger.info("[Scheduler] Starting process task")

    limit = Keyword.get(opts, :limit, 50)
    posts = Posts.list_posts_by_status(Posts.Post.status_new(), limit: limit)

    if Enum.empty?(posts) do
      Logger.info("[Scheduler] No new posts to process")
      {:ok, %{processed: 0, errors: 0}}
    else
      results = Enum.map(posts, &process_single_post/1)

      processed = Enum.count(results, &(&1 == :ok))
      errors = Enum.count(results, &match?({:error, _}, &1))

      Logger.info("[Scheduler] Processing complete: #{processed} posts processed")
      {:ok, %{processed: processed, errors: errors}}
    end
  end

  defp process_single_post(post) do
    case Processor.process_post(post) do
      {:ok, _processed} ->
        :ok

      {:error, reason} ->
        Logger.warning("[Scheduler] Processing failed for post #{post.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Runs the export task: publishes processed articles to Nostr.

  Config:
  - :private_key - Nostr private key (binary, required)
  - :relays - List of relay URLs (required)
  - :limit - Maximum number of posts to export (default: 10)
  - :upload_images - Whether to upload images first (default: false)

  Returns {:ok, %{published: count, errors: count}} or {:error, reason}
  """
  @spec run_export(map()) :: export_result()
  def run_export(config \\ %{}) do
    Logger.info("[Scheduler] Starting export task")

    private_key = config[:private_key]
    relays = config[:relays] || []
    limit = config[:limit] || 10
    upload_images = config[:upload_images] || false

    cond do
      is_nil(private_key) ->
        Logger.warning("[Scheduler] Export skipped: no private key configured")
        {:error, :no_private_key}

      Enum.empty?(relays) ->
        Logger.warning("[Scheduler] Export skipped: no relays configured")
        {:error, :no_relays}

      true ->
        do_export(private_key, relays, limit, upload_images)
    end
  end

  defp do_export(private_key, relays, limit, upload_images) do
    posts = Posts.list_processed_posts(limit: limit)

    if Enum.empty?(posts) do
      Logger.info("[Scheduler] No processed posts to export")
      {:ok, %{published: 0, errors: 0}}
    else
      posts = prepare_posts_for_export(posts, upload_images, private_key)
      results = Publisher.publish_posts(posts, private_key: private_key, relays: relays)

      published = Enum.count(results, fn {_id, r} -> r.success end)
      errors = Enum.count(results, fn {_id, r} -> not r.success end)

      Logger.info(
        "[Scheduler] Export complete: #{published} posts published to #{length(relays)} relays"
      )

      {:ok, %{published: published, errors: errors, relays: length(relays)}}
    end
  end

  defp prepare_posts_for_export(posts, false, _private_key), do: posts

  defp prepare_posts_for_export(posts, true, private_key) do
    Enum.map(posts, &maybe_upload_image(&1, private_key))
  end

  # Upload image to NIP-96 server if needed
  defp maybe_upload_image(post, private_key) do
    url = post.image

    cond do
      is_nil(url) or url == "" ->
        post

      not should_upload?(url) ->
        post

      true ->
        upload_image(post, url, private_key)
    end
  end

  defp upload_image(post, url, private_key) do
    case NIP96.upload_from_url(url, private_key: private_key) do
      {:ok, result} ->
        Logger.debug("[Scheduler] Image uploaded: #{result.url}")
        %{post | image: result.url}

      {:error, reason} ->
        Logger.warning("[Scheduler] Image upload failed: #{inspect(reason)}")
        post
    end
  end

  defp should_upload?(url) do
    known_hosts = ["nostr.build", "nostrcheck.me", "void.cat", "nostpic.com"]
    uri = URI.parse(url)
    host = uri.host || ""
    not Enum.any?(known_hosts, fn h -> String.contains?(host, h) end)
  end
end
