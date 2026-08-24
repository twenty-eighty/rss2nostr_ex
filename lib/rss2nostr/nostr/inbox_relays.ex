defmodule Rss2Nostr.Nostr.InboxRelays do
  @moduledoc """
  Relays used to deliver NIP-17 gift wraps.

  Looks up the recipient kind-0 profile on the public relays, then the NIP-05 `relays` map.
  When that yields nothing, uses the public list (`NOSTR_RELAYS_PUBLIC`).
  `NOSTR_RELAYS_INBOX` is always added. Profile and NIP-05 results are cached.
  """

  require Logger

  alias Rss2Nostr.Nostr.{NIP05, RelayQuery, Relays}

  @cache :inbox_relays_cache
  @ttl_ms :timer.hours(6)

  @spec for_pubkey(String.t(), keyword()) :: [String.t()]
  def for_pubkey(pubkey, opts \\ [])

  def for_pubkey(pubkey, opts) when is_binary(pubkey) do
    hex = String.downcase(String.trim(pubkey))

    cond do
      hex == "" ->
        with_inbox(fallback())

      Keyword.get(opts, :cache, true) && match?({:ok, _}, cache_get(hex)) ->
        {:ok, relays} = cache_get(hex)
        with_inbox(relays)

      true ->
        resolved = resolve(hex, opts)
        if Keyword.get(opts, :cache, true), do: cache_put(hex, resolved)
        with_inbox(resolved)
    end
  end

  def for_pubkey(_, _), do: with_inbox(fallback())

  @spec clear(String.t()) :: :ok
  def clear(pubkey) when is_binary(pubkey) do
    _ = Cachex.del(@cache, String.downcase(String.trim(pubkey)))
    :ok
  rescue
    _ -> :ok
  end

  @spec resolve(String.t(), keyword()) :: [String.t()]
  defp resolve(hex, opts) do
    profile = profile(hex, opts)
    identifier = nip05_identifier(profile)
    nip05_relays = nip05_relays(identifier, hex, opts)

    case nip05_relays do
      [] ->
        fallback()

      relays ->
        relays
    end
  end

  @spec profile(String.t(), keyword()) :: map() | nil
  defp profile(hex, opts) do
    cond do
      Keyword.has_key?(opts, :profile) ->
        Keyword.get(opts, :profile)

      is_function(Keyword.get(opts, :fetch_profile), 1) ->
        opts[:fetch_profile].(hex)

      true ->
        fetch_profile(hex)
    end
  end

  @spec fetch_profile(String.t()) :: map() | nil
  defp fetch_profile(hex) do
    discovery_relays()
    |> RelayQuery.query_relays(%{"authors" => [hex], "kinds" => [0], "limit" => 5})
    |> Enum.max_by(&created_at/1, fn -> nil end)
  end

  @spec nip05_identifier(map() | nil) :: String.t() | nil
  defp nip05_identifier(profile) when is_map(profile) do
    content = field(profile, "content") || field(profile, :content) || ""

    case decode_content(content) do
      {:ok, meta} ->
        case meta["nip05"] || meta[:nip05] do
          value when is_binary(value) -> String.trim(value)
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp nip05_identifier(_), do: nil

  @spec nip05_relays(String.t() | nil, String.t(), keyword()) :: [String.t()]
  defp nip05_relays(nil, _hex, _opts), do: []

  defp nip05_relays(identifier, hex, opts) do
    document =
      cond do
        Keyword.has_key?(opts, :nip05_document) ->
          {:ok, Keyword.get(opts, :nip05_document)}

        is_function(Keyword.get(opts, :fetch_nip05), 1) ->
          opts[:fetch_nip05].(identifier)

        true ->
          NIP05.fetch(identifier)
      end

    case document do
      {:ok, json} when is_map(json) ->
        case NIP05.parse_identifier(identifier) do
          {:ok, name, _domain} -> NIP05.relays_for(json, name, hex)
          :error -> []
        end

      {:ok, _} ->
        []

      {:error, reason} ->
        Logger.debug("NIP-05 lookup failed for #{identifier}: #{inspect(reason)}")
        []

      _ ->
        []
    end
  end

  @spec with_inbox([String.t()]) :: [String.t()]
  defp with_inbox(relays) do
    Enum.uniq(List.wrap(relays) ++ Relays.inbox())
  end

  @spec fallback() :: [String.t()]
  defp fallback, do: Relays.public()

  @spec discovery_relays() :: [String.t()]
  defp discovery_relays do
    Relays.public()
  end

  @spec cache_get(String.t()) :: {:ok, [String.t()]} | :miss
  defp cache_get(hex) do
    case Cachex.get(@cache, hex) do
      {:ok, %{relays: relays}} when is_list(relays) -> {:ok, relays}
      _ -> :miss
    end
  rescue
    _ -> :miss
  end

  @spec cache_put(String.t(), [String.t()]) :: :ok
  defp cache_put(hex, relays) do
    _ = Cachex.put(@cache, hex, %{relays: relays}, expire: @ttl_ms)
    :ok
  rescue
    _ -> :ok
  end

  @spec created_at(map()) :: integer()
  defp created_at(event) do
    case field(event, "created_at") || field(event, :created_at) do
      value when is_integer(value) -> value
      _ -> 0
    end
  end

  @spec field(map(), atom() | String.t()) :: term()
  defp field(map, key), do: Map.get(map, key)

  @spec decode_content(term()) :: {:ok, map()} | :error
  defp decode_content(content) when is_binary(content), do: Jason.decode(content)
  defp decode_content(_), do: :error
end
