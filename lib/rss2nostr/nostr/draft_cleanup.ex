defmodule Rss2Nostr.Nostr.DraftCleanup do
  @moduledoc """
  Deletes app-signed draft events (kind 30024 / 31234) after a kind 30023
  article with the same `d` tag has been published.
  """

  require Logger

  alias Rss2Nostr.Nostr.{Event, Keys, Publisher, Relay, RelayQuery, Relays, Signer}
  alias Rss2Nostr.Posts
  alias Rss2Nostr.Posts.Post

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

  defp do_run(key, opts) do
    query = Keyword.get(opts, :query, &RelayQuery.query_relays/2)
    publish = Keyword.get(opts, :publish, &Relay.publish_to_relays/2)
    limit = Keyword.get(opts, :limit, 50)
    app_pubkey = key |> Keys.derive_public_key() |> Keys.to_hex()

    posts =
      Keyword.get_lazy(opts, :posts, fn ->
        Posts.list_draft_cleanup_candidates(limit: limit)
      end)

    {deleted, skipped} =
      Enum.reduce(posts, {0, 0}, fn post, {deleted, skipped} ->
        case cleanup_post(post, key, app_pubkey, query, publish) do
          :deleted -> {deleted + 1, skipped}
          :skipped -> {deleted, skipped + 1}
        end
      end)

    Logger.info("[Cleanup] Draft cleanup: #{deleted} deleted, #{skipped} still waiting")
    {:ok, %{deleted: deleted, skipped: skipped}}
  end

  defp cleanup_post(%Post{} = post, key, app_pubkey, query, publish) do
    identifier = Publisher.identifier(post)
    lookup = lookup_relays()
    delete_on = delete_relays()

    cond do
      identifier == "" or lookup == [] or delete_on == [] ->
        :skipped

      query.(lookup, article_filter(post, identifier)) == [] ->
        :skipped

      true ->
        drafts = query.(lookup, draft_filter(app_pubkey, identifier))

        deletion =
          Event.build_deletion(app_pubkey,
            event_ids: draft_event_ids(post, drafts),
            addresses: draft_addresses(app_pubkey, identifier),
            reason: @reason
          )

        case Event.sign_event(deletion, key) do
          {:ok, signed} ->
            results = publish.(delete_on, signed)
            ok? = Enum.any?(results, fn {_url, result} -> result == :ok end)

            if ok? do
              _ = Posts.mark_draft_cleaned(post)
              Logger.info("[Cleanup] Deleted drafts for post #{post.id} (#{identifier})")
              :deleted
            else
              Logger.warning(
                "[Cleanup] Deletion rejected for post #{post.id}: #{inspect(results)}"
              )

              :skipped
            end

          {:error, reason} ->
            Logger.warning(
              "[Cleanup] Could not sign deletion for post #{post.id}: #{inspect(reason)}"
            )

            :skipped
        end
    end
  end

  defp article_filter(post, identifier) do
    filter = %{"kinds" => [Event.kind_long_form()], "#d" => [identifier], "limit" => 5}

    case source_author(post) do
      nil -> filter
      author -> Map.put(filter, "authors", [author])
    end
  end

  defp draft_filter(app_pubkey, identifier) do
    %{
      "kinds" => [Event.kind_long_form_draft(), Event.kind_draft_wrap()],
      "authors" => [app_pubkey],
      "#d" => [identifier],
      "limit" => 20
    }
  end

  defp draft_event_ids(post, drafts) do
    found = Enum.map(drafts, &event_id/1)

    [post.event_id | found]
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.uniq()
  end

  defp draft_addresses(app_pubkey, identifier) do
    [
      "#{Event.kind_long_form_draft()}:#{app_pubkey}:#{identifier}",
      "#{Event.kind_draft_wrap()}:#{app_pubkey}:#{identifier}"
    ]
  end

  defp source_author(post) do
    pubkey = post.source && post.source.pubkey

    if Keys.valid_pubkey?(pubkey), do: String.downcase(pubkey)
  end

  defp lookup_relays do
    Relays.draft() ++ Relays.test() ++ Relays.public()
  end

  defp delete_relays do
    case Relays.draft() do
      [] -> Relays.test() ++ Relays.public()
      list -> list
    end
  end

  defp event_id(%{"id" => id}), do: id
  defp event_id(%{id: id}), do: id
  defp event_id(_), do: nil
end
