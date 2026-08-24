defmodule Rss2Nostr.Nostr.DraftCleanup do
  @moduledoc """
  Deletes app-signed draft events (kind 30024 / 31234) after a kind 30023
  article with the same `d` tag has been published by the author named in
  the draft's `p` tag.

  Scans relays for every draft authored by `NOSTR_PRIVATE_KEY`, not only
  drafts that came from a known RSS source.
  """

  require Logger

  alias Rss2Nostr.Nostr.{Event, Keys, Publisher, Relay, RelayQuery, Relays, Signer}
  alias Rss2Nostr.Posts

  @reason "replaced by published article"

  @spec run(keyword()) :: {:ok, map()} | {:error, atom()}
  def run(opts \\ []) do
    case Signer.app_signer() do
      {:ok, {:private_key, key}} ->
        do_run(key, opts)

      {:error, reason} ->
        Logger.warning("[Cleanup] Skipped: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @spec do_run(binary(), keyword()) :: {:ok, %{deleted: non_neg_integer(), skipped: non_neg_integer()}} | {:error, atom()}
  defp do_run(key, opts) do
    query = Keyword.get(opts, :query, &RelayQuery.query_relays/2)
    publish = Keyword.get(opts, :publish, &Relay.publish_to_relays/2)
    limit = Keyword.get(opts, :limit, 200)
    app_pubkey = key |> Keys.derive_public_key() |> Keys.to_hex()
    lookup = lookup_relays()
    delete_on = delete_relays()

    drafts =
      Keyword.get_lazy(opts, :drafts, fn ->
        query.(lookup, all_drafts_filter(app_pubkey, limit))
      end)

    posts =
      Keyword.get_lazy(opts, :posts, fn ->
        Posts.list_draft_cleanup_candidates(limit: limit)
      end)

    groups = draft_groups(drafts, posts)
    published = published_keys(groups, query, lookup)

    {deleted, skipped} =
      Enum.reduce(groups, {0, 0}, fn group, {deleted, skipped} ->
        case cleanup_group(group, key, app_pubkey, published, delete_on, publish, posts) do
          :deleted -> {deleted + 1, skipped}
          :skipped -> {deleted, skipped + 1}
        end
      end)

    Logger.info("[Cleanup] Draft cleanup: #{deleted} deleted, #{skipped} still waiting")
    {:ok, %{deleted: deleted, skipped: skipped}}
  end

  @spec cleanup_group(map(), binary(), String.t(), MapSet.t(), [String.t()], term(), list()) :: :deleted | :skipped
  defp cleanup_group(group, key, app_pubkey, published, delete_on, publish, posts) do
    %{identifier: identifier, author: author, event_ids: event_ids} = group

    cond do
      identifier == "" or author == nil or delete_on == [] ->
        :skipped

      not MapSet.member?(published, {identifier, author}) ->
        :skipped

      true ->
        deletion =
          Event.build_deletion(app_pubkey,
            event_ids: event_ids,
            addresses: draft_addresses(app_pubkey, identifier),
            reason: @reason
          )

        case Event.sign_event(deletion, key) do
          {:ok, signed} ->
            results = publish.(delete_on, signed)
            ok? = Enum.any?(results, fn {_url, result} -> result == :ok end)

            if ok? do
              mark_local_posts(posts, identifier, author)
              Logger.info("[Cleanup] Deleted drafts for d=#{identifier} p=#{author}")
              :deleted
            else
              Logger.warning(
                "[Cleanup] Deletion rejected for d=#{identifier}: #{inspect(results)}"
              )

              :skipped
            end

          {:error, reason} ->
            Logger.warning(
              "[Cleanup] Could not sign deletion for d=#{identifier}: #{inspect(reason)}"
            )

            :skipped
        end
    end
  end

  @spec draft_groups(list(), list()) :: [map()]
  defp draft_groups(drafts, posts) do
    %{}
    |> add_draft_events(drafts)
    |> add_local_posts(posts)
    |> Enum.map(fn {{identifier, author}, event_ids} ->
      %{
        identifier: identifier,
        author: author,
        event_ids: event_ids |> Enum.reject(&(&1 in [nil, ""])) |> Enum.uniq()
      }
    end)
  end

  @spec add_draft_events(map(), list()) :: map()
  defp add_draft_events(groups, drafts) do
    Enum.reduce(drafts, groups, fn event, acc ->
      identifier = tag_value(event, "d")
      author = author_p_tag(event)

      if identifier != "" and author do
        Map.update(acc, {identifier, author}, compact_ids([event_id(event)]), fn ids ->
          compact_ids([event_id(event) | ids])
        end)
      else
        acc
      end
    end)
  end

  @spec add_local_posts(map(), list()) :: map()
  defp add_local_posts(groups, posts) do
    Enum.reduce(posts, groups, fn post, acc ->
      identifier = Publisher.identifier(post)
      author = source_author(post)

      if identifier != "" and author do
        Map.update(acc, {identifier, author}, compact_ids([post.event_id]), fn ids ->
          compact_ids([post.event_id | ids])
        end)
      else
        acc
      end
    end)
  end

  @spec mark_local_posts(list(), String.t(), String.t()) :: :ok
  defp mark_local_posts(posts, identifier, author) do
    posts
    |> Enum.filter(fn post ->
      Publisher.identifier(post) == identifier and source_author(post) == author
    end)
    |> Enum.each(fn post ->
      _ = Posts.mark_draft_cleaned(post)
    end)
  end

  @spec all_drafts_filter(String.t(), pos_integer()) :: map()
  defp all_drafts_filter(app_pubkey, limit) do
    %{
      "kinds" => [Event.kind_long_form_draft(), Event.kind_draft_wrap()],
      "authors" => [app_pubkey],
      "limit" => limit
    }
  end

  @spec published_keys(list(), term(), [String.t()]) :: MapSet.t()
  defp published_keys([], _query, _urls), do: MapSet.new()

  defp published_keys(groups, query, urls) do
    groups
    |> Enum.group_by(& &1.author, & &1.identifier)
    |> Enum.reduce(MapSet.new(), fn {author, identifiers}, acc ->
      ids = Enum.uniq(identifiers)

      query.(urls, article_filter(ids, author))
      |> Enum.reduce(acc, fn event, acc ->
        identifier = tag_value(event, "d")
        event_author = normalize_pubkey(event_pubkey(event))

        if identifier in ids and event_author == author do
          MapSet.put(acc, {identifier, author})
        else
          acc
        end
      end)
    end)
  end

  @spec article_filter(list(), String.t()) :: map()
  defp article_filter(identifiers, author) do
    ids = List.wrap(identifiers)

    %{
      "kinds" => [Event.kind_long_form()],
      "#d" => ids,
      "authors" => [author],
      "limit" => max(length(ids), 5)
    }
  end

  @spec event_pubkey(map()) :: String.t() | nil
  defp event_pubkey(event) do
    event["pubkey"] || event[:pubkey]
  end

  @spec draft_addresses(String.t(), String.t()) :: [String.t()]
  defp draft_addresses(app_pubkey, identifier) do
    [
      "#{Event.kind_long_form_draft()}:#{app_pubkey}:#{identifier}",
      "#{Event.kind_draft_wrap()}:#{app_pubkey}:#{identifier}"
    ]
  end

  @spec source_author(map()) :: String.t() | nil
  defp source_author(post) do
    pubkey = post.source && post.source.pubkey
    normalize_pubkey(pubkey)
  end

  @spec author_p_tag(map()) :: String.t() | nil
  defp author_p_tag(event) do
    event
    |> tag_values("p")
    |> Enum.find_value(&normalize_pubkey/1)
  end

  @spec normalize_pubkey(String.t() | nil) :: String.t() | nil
  defp normalize_pubkey(pubkey) do
    if Keys.valid_pubkey?(pubkey), do: String.downcase(pubkey)
  end

  @spec tag_value(map(), String.t()) :: String.t()
  defp tag_value(event, name) do
    event
    |> tag_values(name)
    |> List.first()
    |> case do
      value when is_binary(value) -> value
      _ -> ""
    end
  end

  @spec tag_values(map(), String.t()) :: [String.t()]
  defp tag_values(event, name) do
    event
    |> event_tags()
    |> Enum.flat_map(fn
      [tag, value | _] when tag == name and is_binary(value) and value != "" -> [value]
      _ -> []
    end)
  end

  @spec event_tags(map()) :: list()
  defp event_tags(event) do
    event[:tags] || event["tags"] || []
  end

  @spec compact_ids(list()) :: [String.t()]
  defp compact_ids(ids) do
    ids
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.uniq()
  end

  @spec lookup_relays() :: [String.t()]
  defp lookup_relays do
    Enum.uniq(Relays.draft() ++ Relays.test() ++ Relays.public())
  end

  @spec delete_relays() :: [String.t()]
  defp delete_relays do
    case Relays.draft() do
      [] -> Enum.uniq(Relays.test() ++ Relays.public())
      list -> Enum.uniq(list)
    end
  end

  @spec event_id(map()) :: String.t() | nil
  defp event_id(%{"id" => id}), do: id
  defp event_id(%{id: id}), do: id
  defp event_id(_), do: nil
end
