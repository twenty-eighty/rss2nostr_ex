defmodule Rss2Nostr.Import.Importer do
  @moduledoc """
  Orchestrates the import of articles from RSS/Atom feeds.
  """

  require Logger

  alias Rss2Nostr.Sources
  alias Rss2Nostr.Sources.Source
  alias Rss2Nostr.Posts
  alias Rss2Nostr.Posts.Post
  alias Rss2Nostr.Import.{FeedFetcher, FeedParser, ItemIdentity}
  alias Rss2Nostr.Processing.Composer

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
      start_guid = source_start_guid(source)
      guid_in_feed? = start_guid && Enum.any?(items, &(&1.guid == start_guid))

      # Process items in reverse order (oldest first) for proper publish sequence
      items
      |> Enum.reverse()
      |> Enum.reduce({result, false}, fn item, {acc, started?} ->
        case import_item(item, source, force, started?, guid_in_feed?, start_guid) do
          {:ok, :imported, started?} ->
            {%{acc | imported: acc.imported + 1}, started?}

          {:ok, :skipped, started?} ->
            {%{acc | skipped: acc.skipped + 1}, started?}

          {:error, reason, started?} ->
            {%{acc | errors: [reason | acc.errors]}, started?}
        end
      end)
      |> elem(0)
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
  defp import_item(item, source, force, started?, guid_in_feed?, start_guid) do
    reached_start? = started? or (guid_in_feed? and item.guid == start_guid)
    url_hash = Post.generate_url_hash(item.guid)

    cond do
      guid_in_feed? and not reached_start? ->
        {:ok, :skipped, false}

      is_nil(item.guid) ->
        Logger.debug("Skipping item without guid: #{item.title}")
        {:ok, :skipped, reached_start?}

      ItemIdentity.media_without_page?(item) ->
        Logger.debug("Skipping media without page: #{item.title}")
        {:ok, :skipped, reached_start?}

      !force && Posts.exists_by_url_hash?(url_hash, source.id) ->
        Logger.debug("Skipping duplicate: #{item.title}")
        {:ok, :skipped, reached_start?}

      !force && duplicate_identity?(item, source) ->
        Logger.debug("Skipping duplicate: #{item.title}")
        {:ok, :skipped, reached_start?}

      should_skip_by_date?(item, source) ->
        Logger.debug("Skipping by date filter: #{item.title}")
        {:ok, :skipped, reached_start?}

      true ->
        case adopt_or_create_post(item, source, url_hash, force) do
          {:ok, status} -> {:ok, status, reached_start?}
          {:error, reason} -> {:error, reason, reached_start?}
        end
    end
  end

  defp adopt_or_create_post(item, source, url_hash, true) do
    create_post(item, source, url_hash, true)
  end

  defp adopt_or_create_post(item, source, url_hash, false) do
    case Posts.adopt_orphaned_by_url_hash(url_hash, source.id) do
      {:ok, post} ->
        Logger.info("Reattached existing post: #{post.title}")
        {:ok, :imported}

      :none ->
        create_post(item, source, url_hash, false)

      {:error, changeset} ->
        {:error, "Reattach failed: #{inspect(changeset.errors)}"}
    end
  end

  defp resolve_source_html(item, source) do
    case Composer.html_for_item(item, source) do
      {:ok, html, _source} -> {:ok, html}
      {:error, reason} -> {:error, "Could not load article HTML: #{reason}"}
    end
  end

  defp duplicate_identity?(item, source) do
    Posts.exists_by_identity?(ItemIdentity.identity_values(item), pubkey: source.pubkey)
  end

  defp source_start_guid(%Source{options: options}) when is_map(options) do
    case options["start_guid"] || options[:start_guid] do
      guid when is_binary(guid) and guid != "" -> guid
      _ -> nil
    end
  end

  defp source_start_guid(_), do: nil

  defp should_skip_by_date?(item, source) do
    case {source.publish_after_date, item.published_at} do
      {nil, _} -> false
      {_, nil} -> false
      {after_date, pub_date} -> DateTime.compare(pub_date, after_date) == :lt
    end
  end

  defp create_post(item, source, url_hash, force) do
    with {:ok, source_html} <- resolve_source_html(item, source) do
      attrs = %{
        article_identifier: item.guid,
        title: item.title,
        source_html: source_html,
        source_url: item.link || ItemIdentity.page_url(item),
        source_url_hash: url_hash,
        published_at: item.published_at,
        imported_at: DateTime.utc_now(),
        author_name: item.author,
        summary: truncate_summary(item.summary),
        image: item.image,
        language: source.language,
        categories: item.categories || [],
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
  end

  defp force_create_or_update(attrs, url_hash, title) do
    existing =
      Posts.get_post_by_url_hash(url_hash, attrs.source_id) ||
        case Posts.adopt_orphaned_by_url_hash(url_hash, attrs.source_id) do
          {:ok, post} -> post
          _ -> nil
        end

    case existing do
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
