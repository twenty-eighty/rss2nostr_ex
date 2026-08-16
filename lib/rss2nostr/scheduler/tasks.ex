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
  alias Rss2Nostr.Nostr.{DraftCleanup, Publisher, Relays, Signer}

  @type import_result ::
          {:ok,
           %{imported: non_neg_integer(), errors: non_neg_integer(), sources: non_neg_integer()}}
  @type process_result :: {:ok, %{processed: non_neg_integer(), errors: non_neg_integer()}}
  @type export_result ::
          {:ok, %{published: non_neg_integer(), errors: non_neg_integer()}} | {:error, atom()}
  @type cleanup_result ::
          {:ok, %{deleted: non_neg_integer(), skipped: non_neg_integer()}} | {:error, atom()}

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
    posts = Posts.list_processable_posts(limit: limit)

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
  - :private_key - App key used for draft sources (optional if every source has its own signer)
  - :relays - Explicit relay URLs (public relays are dropped for setup sources)
  - :audience - `:test` or `:public` (ignored for setup sources)
  - :limit - Maximum number of posts to export (default: 10)
  - :upload_images - Ignored; images are uploaded during process, before a post is processed

  Returns {:ok, %{published: count, errors: count}} or {:error, reason}
  """
  @spec run_export(map()) :: export_result()
  def run_export(config \\ %{}) do
    Logger.info("[Scheduler] Starting export task")

    relays = Map.get(config, :relays, :per_post)
    audience = Relays.parse_audience(config[:audience])
    limit = config[:limit] || 10

    cond do
      relays == [] ->
        Logger.warning("[Scheduler] Export skipped: no relays configured")
        {:error, :no_relays}

      relays == :per_post and Relays.empty?() ->
        Logger.warning("[Scheduler] Export skipped: no relays configured")
        {:error, :no_relays}

      true ->
        do_export(config, relays, audience, limit)
    end
  end

  defp do_export(config, relays, audience, limit) do
    posts = Posts.list_exportable_posts(limit: limit)

    if Enum.empty?(posts) do
      Logger.info("[Scheduler] No staging posts ready to export")
      {:ok, %{published: 0, errors: 0}}
    else
      results = Publisher.each_with_gap(posts, &export_post(&1, config, relays, audience))

      published = Enum.count(results, fn {_id, r} -> r.success end)
      errors = Enum.count(results, fn {_id, r} -> not r.success end)

      Logger.info("[Scheduler] Export complete: #{published} published, #{errors} not published")

      {:ok, %{published: published, errors: errors}}
    end
  end

  defp export_post(post, config, relays, audience) do
    case Signer.resolve(post.source, private_key: config[:private_key]) do
      {:ok, signer} ->
        opts = publish_opts(signer, post, relays, audience)

        case Publisher.publish_post(post, opts) do
          {:ok, result} -> {post.id, result}
          {:error, reason} -> {post.id, %{success: false, error: reason}}
        end

      {:error, reason} ->
        Logger.warning(
          "[Scheduler] Export skipped for post #{post.id}: no signer (#{inspect(reason)})"
        )

        {post.id, %{success: false, error: reason}}
    end
  end

  defp publish_opts(signer, post, relays, audience) when is_list(relays) do
    [signer: signer, relays: Relays.publish_relays(post, relays: relays, audience: audience)]
  end

  defp publish_opts(signer, post, :per_post, audience) do
    [signer: signer, relays: Relays.publish_relays(post, audience: audience)]
  end

  @doc """
  Deletes app-signed drafts after the same article exists as kind 30023.
  """
  @spec run_cleanup(keyword()) :: cleanup_result()
  def run_cleanup(opts \\ []) do
    Logger.info("[Scheduler] Starting draft cleanup task")
    DraftCleanup.run(opts)
  end
end
