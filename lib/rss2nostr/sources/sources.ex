defmodule Rss2Nostr.Sources do
  @moduledoc """
  Context for managing RSS/Atom feed sources.
  """

  import Ecto.Query
  alias Rss2Nostr.Repo
  alias Rss2Nostr.Posts.Post
  alias Rss2Nostr.Sources.Source

  @doc """
  Returns all sources.

  Article and video sources missing a stored author pubkey are backfilled from
  siblings that share the same notify pubkey when that pubkey is unambiguous.
  """
  @spec list_sources() :: [Source.t()]
  def list_sources do
    maybe_backfill_author_pubkeys()
    Repo.all(Source)
  end

  @doc """
  Returns all active sources.
  """
  @spec list_active_sources() :: [Source.t()]
  def list_active_sources do
    Source
    |> where([s], s.active == true)
    |> Repo.all()
  end

  @doc """
  Gets a single source by ID.
  """
  @spec get_source(integer() | binary()) :: Source.t() | nil
  def get_source(id), do: Repo.get(Source, id)

  @doc """
  Gets a single source by ID, raises if not found.
  """
  @spec get_source!(integer() | binary()) :: Source.t()
  def get_source!(id), do: Repo.get!(Source, id)

  @doc """
  Gets a source by URL.
  """
  @spec get_source_by_url(String.t()) :: Source.t() | nil
  def get_source_by_url(url) do
    Repo.get_by(Source, url: url)
  end

  @doc """
  Creates a new source.
  """
  @spec create_source(map()) :: {:ok, Source.t()} | {:error, Ecto.Changeset.t()}
  def create_source(attrs \\ %{}) do
    %Source{}
    |> Source.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a source.
  """
  @spec update_source(Source.t(), map()) :: {:ok, Source.t()} | {:error, Ecto.Changeset.t()}
  def update_source(%Source{} = source, attrs) do
    result =
      source
      |> Source.changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, updated} ->
        sync_post_kinds(updated)
        {:ok, updated}

      error ->
        error
    end
  end

  @spec sync_post_kinds(Source.t()) :: {non_neg_integer(), nil}
  defp sync_post_kinds(%Source{id: id, default_post_kind: kind})
       when kind in [30023, 30024, 34235] do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Post
    |> where([p], p.source_id == ^id and p.type != ^kind)
    |> Repo.update_all(set: [type: kind, updated_at: now])
  end

  defp sync_post_kinds(_), do: {0, nil}

  @doc """
  Deletes a source and all of its articles.
  """
  @spec delete_source(Source.t()) :: {:ok, Source.t()} | {:error, Ecto.Changeset.t()}
  def delete_source(%Source{} = source) do
    Repo.delete(source)
  end

  @doc """
  Copies a source's settings into a new source without its posts.

  The copy starts in setup mode. The feed URL must be unique, so a
  marker is added unless `:url` is given. Composition settings are
  kept; the import start position is reset.
  """
  @spec duplicate_source(Source.t(), map()) :: {:ok, Source.t()} | {:error, Ecto.Changeset.t()}
  def duplicate_source(%Source{} = source, attrs \\ %{}) do
    %{
      name: attr(attrs, :name) || "#{source.name} (copy)",
      url: attr(attrs, :url) || unique_copy_url(source.url),
      type: source.type,
      language: source.language,
      public: source.public,
      active: true,
      mode: "setup",
      default_post_kind: source.default_post_kind,
      pubkey: source.pubkey,
      bunker_connection: source.bunker_connection,
      signing_nsec_ciphertext: source.signing_nsec_ciphertext,
      fetch_source_from: source.fetch_source_from,
      staging_hold_minutes: source.staging_hold_minutes || 0,
      notify_pubkey: source.notify_pubkey,
      fixed_hashtags: source.fixed_hashtags || [],
      excluded_hashtags: source.excluded_hashtags || [],
      options: copy_options(source.options)
    }
    |> maybe_put_publish_as(source)
    |> create_source()
  end

  @spec maybe_put_publish_as(map(), Source.t()) :: map()
  defp maybe_put_publish_as(attrs, source) do
    if source.publish_as in ["article", "video", "draft_plain"] or present_binary?(source.pubkey) do
      Map.put(attrs, :publish_as, source.publish_as)
    else
      attrs
    end
  end

  @spec present_binary?(term()) :: boolean()
  defp present_binary?(value) when is_binary(value), do: String.trim(value) != ""
  defp present_binary?(_), do: false

  @spec attr(map(), atom()) :: String.t() | nil
  @spec attr(map(), atom()) :: String.t() | nil
  defp attr(attrs, key) do
    value = Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))

    case value do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          trimmed -> trimmed
        end

      _ ->
        nil
    end
  end

  @spec unique_copy_url(String.t()) :: String.t()
  defp unique_copy_url(url) do
    marker = "rss2nostr_copy=#{System.unique_integer([:positive])}"

    if String.contains?(url, "?") do
      url <> "&" <> marker
    else
      url <> "?" <> marker
    end
  end

  @spec copy_options(map() | term()) :: map()
  defp copy_options(options) when is_map(options), do: Map.drop(options, ["start_guid"])
  defp copy_options(_), do: %{}

  @doc """
  Enables a source (by struct or ID).
  """
  @spec enable_source(Source.t() | integer() | binary()) ::
          {:ok, Source.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def enable_source(%Source{} = source) do
    update_source(source, %{active: true})
  end

  def enable_source(id) when is_integer(id) or is_binary(id) do
    case get_source(id) do
      nil -> {:error, :not_found}
      source -> enable_source(source)
    end
  end

  @doc """
  Disables a source (by struct or ID).
  """
  @spec disable_source(Source.t() | integer() | binary()) ::
          {:ok, Source.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def disable_source(%Source{} = source) do
    update_source(source, %{active: false})
  end

  def disable_source(id) when is_integer(id) or is_binary(id) do
    case get_source(id) do
      nil -> {:error, :not_found}
      source -> disable_source(source)
    end
  end

  @doc """
  Returns a changeset for tracking source changes.
  """
  @spec change_source(Source.t(), map()) :: Ecto.Changeset.t()
  def change_source(%Source{} = source, attrs \\ %{}) do
    Source.changeset(source, attrs)
  end

  @doc """
  Returns the total count of sources.
  """
  @spec count_sources() :: non_neg_integer()
  def count_sources do
    Repo.aggregate(Source, :count, :id)
  end

  @article_publish_as ~w(article video)

  @doc """
  Fills missing author pubkeys on article and video sources.

  First tries to derive the pubkey from each source nsec. When that fails, copies
  the pubkey from another source with the same notify pubkey when only one pubkey
  exists in that group.
  """
  @spec backfill_author_pubkeys() :: non_neg_integer()
  def backfill_author_pubkeys do
    case :persistent_term.get({__MODULE__, :author_pubkey_backfill}, false) do
      true ->
        0

      false ->
        count = do_backfill_author_pubkeys()
        :persistent_term.put({__MODULE__, :author_pubkey_backfill}, true)
        count
    end
  end

  @spec maybe_backfill_author_pubkeys() :: :ok
  defp maybe_backfill_author_pubkeys do
    case :persistent_term.get({__MODULE__, :author_pubkey_backfill}, false) do
      true -> :ok
      false -> _ = backfill_author_pubkeys(); :ok
    end
  end

  @spec do_backfill_author_pubkeys() :: non_neg_integer()
  defp do_backfill_author_pubkeys do
    query =
      Source
      |> where([s], s.publish_as in ^@article_publish_as)

    sources = Repo.all(query)

    derived =
      sources
      |> Enum.filter(&is_nil(&1.pubkey))
      |> Enum.reduce(0, fn source, count ->
        case update_source(source, %{}) do
          {:ok, %{pubkey: pubkey}} when is_binary(pubkey) -> count + 1
          _ -> count
        end
      end)

    copied =
      query
      |> Repo.all()
      |> Enum.group_by(&backfill_group_key/1)
      |> Enum.reduce(0, fn {_key, group}, count ->
        count + copy_group_pubkey(group)
      end)

    derived + copied
  end

  @spec backfill_group_key(Source.t()) :: term()
  defp backfill_group_key(%Source{notify_pubkey: notify})
       when is_binary(notify) and notify != "" do
    {:notify, notify}
  end

  defp backfill_group_key(%Source{id: id}), do: {:solo, id}

  @spec copy_group_pubkey([Source.t()]) :: non_neg_integer()
  defp copy_group_pubkey(group) do
    pubkeys =
      group
      |> Enum.map(& &1.pubkey)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    case pubkeys do
      [pubkey] ->
        group
        |> Enum.filter(&is_nil(&1.pubkey))
        |> Enum.reduce(0, fn source, count ->
          case update_source(source, %{pubkey: pubkey}) do
            {:ok, _} -> count + 1
            _ -> count
          end
        end)

      _ ->
        0
    end
  end

  @doc """
  Returns the count of active sources.
  """
  @spec count_active_sources() :: non_neg_integer()
  def count_active_sources do
    Source
    |> where([s], s.active == true)
    |> Repo.aggregate(:count, :id)
  end
end
