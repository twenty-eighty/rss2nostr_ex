defmodule Rss2Nostr.Nostr.RelayQuery do
  @moduledoc """
  One-shot REQ queries against Nostr relays.

  Uses the pooled `Relay` connections so a later publish to the same URL
  does not open a second socket.
  """

  require Logger

  alias Rss2Nostr.Nostr.Relay

  @default_timeout 8_000

  @doc """
  Queries `filter` on each URL and returns unique events by id.
  Connection or timeout failures are skipped.
  """
  @spec query_relays([String.t()], map(), keyword()) :: [map()]
  def query_relays(urls, filter, opts \\ []) when is_list(urls) and is_map(filter) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    urls
    |> Enum.uniq()
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Task.async_stream(
      fn url ->
        case Relay.query(url, filter, timeout) do
          {:ok, events} ->
            events

          {:error, reason} ->
            Logger.debug("Relay query failed for #{url}: #{inspect(reason)}")
            []
        end
      end,
      timeout: timeout + 1_000,
      ordered: false,
      on_timeout: :kill_task
    )
    |> Enum.flat_map(fn
      {:ok, events} -> events
      _ -> []
    end)
    |> Enum.uniq_by(&event_id/1)
    |> Enum.reject(&is_nil(event_id(&1)))
  end

  @spec event_id(map()) :: String.t() | nil
  defp event_id(%{"id" => id}) when is_binary(id), do: id
  defp event_id(%{id: id}) when is_binary(id), do: id
  defp event_id(_), do: nil
end
