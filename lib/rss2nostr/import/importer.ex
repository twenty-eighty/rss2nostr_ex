defmodule Rss2Nostr.Import.Importer do
  @moduledoc """
  Orchestrates the import of articles from RSS/Atom feeds.
  """

  require Logger

  alias Rss2Nostr.Sources
  alias Rss2Nostr.Sources.Source
  alias Rss2Nostr.Posts
  alias Rss2Nostr.Posts.Post
  alias Rss2Nostr.Import.{FeedFetcher, FeedParser}

  @type import_result :: %{
          source: Source.t(),
          imported: non_neg_integer(),
          skipped: non_neg_integer(),
          errors: [String.t()]
        }

  @doc """
  Imports articles from all active sources.
  Returns a list of import results.
  """
  @spec import_all(keyword()) :: [import_result()]
  def import_all(opts \\ []) do
    force = Keyword.get(opts, :force, false)

    Sources.list_active_sources()
    |> Enum.map(fn source ->
      import_from_source(source, force: force)
    end)
  end

  @doc """
  Imports articles from a specific source.
  """
  @spec import_from_source(Source.t(), keyword()) :: import_result()
  def import_from_source(%Source{} = source, opts \\ []) do
    force = Keyword.get(opts, :force, false)

    Logger.info("Importing from source: #{source.name} (#{source.url})")

    result = %{
      source: source,
      imported: 0,
      skipped: 0,
      errors: []
    }

    with {:ok, body} <- FeedFetcher.fetch(source.url),
         {:ok, items} <- FeedParser.parse(body, source.type) do
      # Process items in reverse order (oldest first) for proper publish sequence
      items
      |> Enum.reverse()
      |> Enum.reduce(result, fn item, acc ->
        case import_item(item, source, force) do
          {:ok, :imported} ->
            %{acc | imported: acc.imported + 1}

          {:ok, :skipped} ->
            %{acc | skipped: acc.skipped + 1}

          {:error, reason} ->
            %{acc | errors: [reason | acc.errors]}
        end
      end)
    else
      {:error, reason} ->
        Logger.error("Failed to fetch/parse feed #{source.name}: #{inspect(reason)}")
        %{result | errors: [inspect(reason)]}
    end
  end

  @doc """
  Imports articles from a source by ID.
  """
  @spec import_from_source_id(integer() | binary(), keyword()) ::
          {:ok, import_result()} | {:error, :source_not_found}
  def import_from_source_id(source_id, opts \\ []) do
    case Sources.get_source(source_id) do
      nil -> {:error, :source_not_found}
      source -> {:ok, import_from_source(source, opts)}
    end
  end

  # Import a single feed item
  defp import_item(item, source, force) do
    url_hash = Post.generate_url_hash(item.guid)

    cond do
      is_nil(item.guid) ->
        Logger.debug("Skipping item without guid: #{item.title}")
        {:ok, :skipped}

      !force && Posts.exists_by_url_hash?(url_hash) ->
        Logger.debug("Skipping duplicate: #{item.title}")
        {:ok, :skipped}

      should_skip_by_date?(item, source) ->
        Logger.debug("Skipping by date filter: #{item.title}")
        {:ok, :skipped}

      true ->
        create_post(item, source, url_hash, force)
    end
  end

  defp should_skip_by_date?(item, source) do
    case {source.publish_after_date, item.published_at} do
      {nil, _} -> false
      {_, nil} -> false
      {after_date, pub_date} -> DateTime.compare(pub_date, after_date) == :lt
    end
  end

  defp create_post(item, source, url_hash, force) do
    attrs = %{
      article_identifier: item.guid,
      title: item.title,
      source_html: item.content || item.summary,
      source_url: item.link,
      source_url_hash: url_hash,
      published_at: item.published_at,
      imported_at: DateTime.utc_now(),
      author_name: item.author,
      summary: truncate_summary(item.summary),
      image: item.image,
      language: source.language,
      type: source.default_post_kind,
      pubkey: source.pubkey,
      source_id: source.id,
      status: Post.status_new()
    }

    if force do
      force_create_or_update(attrs, url_hash, item.title)
    else
      do_create_post(attrs)
    end
  end

  defp force_create_or_update(attrs, url_hash, title) do
    case Posts.get_post_by_url_hash(url_hash) do
      nil ->
        do_create_post(attrs)

      existing ->
        do_update_post(existing, attrs, title)
    end
  end

  defp do_update_post(existing, attrs, title) do
    case Posts.update_post(existing, Map.put(attrs, :status, Post.status_new())) do
      {:ok, _} ->
        Logger.info("Updated existing post: #{title}")
        {:ok, :imported}

      {:error, changeset} ->
        {:error, "Update failed: #{inspect(changeset.errors)}"}
    end
  end

  defp do_create_post(attrs) do
    case Posts.create_post(attrs) do
      {:ok, post} ->
        Logger.info("Imported: #{post.title}")
        {:ok, :imported}

      {:error, changeset} ->
        {:error, "Insert failed: #{inspect(changeset.errors)}"}
    end
  end

  defp truncate_summary(nil), do: nil

  defp truncate_summary(text) when byte_size(text) > 500 do
    text
    |> String.slice(0, 497)
    |> Kernel.<>("...")
  end

  defp truncate_summary(text), do: text
end
