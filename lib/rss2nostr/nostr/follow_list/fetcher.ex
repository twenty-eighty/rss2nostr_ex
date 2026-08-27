defmodule Rss2Nostr.Nostr.FollowList.Fetcher do
  @moduledoc """
  Loads followed author pubkeys from a Nostr kind-3 contact list.
  """

  alias Rss2Nostr.Nostr.{Keys, RelayQuery, Relays}

  @type relay_event :: %{
          optional(String.t()) => String.t() | integer() | list(),
          optional(atom()) => String.t() | integer() | list()
        }

  @doc """
  Fetches the latest kind-3 contact list for `pubkey` and returns followed pubkeys.
  """
  @spec fetch(String.t(), keyword()) :: {:ok, MapSet.t(String.t())} | {:error, term()}
  def fetch(pubkey, opts \\ []) when is_binary(pubkey) do
    query = Keyword.get(opts, :query, &RelayQuery.query_relays/2)
    relays = Keyword.get(opts, :relays, Relays.public())

    events =
      query.(relays, %{
        "authors" => [pubkey],
        "kinds" => [3],
        "limit" => 5
      })

    case latest_event(events) do
      nil -> {:ok, MapSet.new()}
      event -> {:ok, members_from_event(event)}
    end
  rescue
    error -> {:error, error}
  end

  @doc """
  Extracts lowercase hex pubkeys from `p` tags on a contact-list event.
  """
  @spec members_from_event(relay_event()) :: MapSet.t(String.t())
  def members_from_event(event) when is_map(event) do
    tags = Map.get(event, "tags") || Map.get(event, :tags) || []

    tags
    |> Enum.flat_map(fn
      ["p", pubkey | _] when is_binary(pubkey) ->
        pubkey = String.downcase(String.trim(pubkey))
        if Keys.valid_pubkey?(pubkey), do: [pubkey], else: []

      _ ->
        []
    end)
    |> MapSet.new()
  end

  @spec latest_event([relay_event()]) :: relay_event() | nil
  defp latest_event(events) when is_list(events) do
    Enum.max_by(events, &created_at/1, fn -> nil end)
  end

  @spec created_at(relay_event()) :: integer()
  defp created_at(event) do
    case Map.get(event, "created_at") || Map.get(event, :created_at) do
      value when is_integer(value) -> value
      _ -> 0
    end
  end
end
