defmodule Rss2Nostr.Nostr.RelayQuery do
  @moduledoc """
  One-shot REQ queries against Nostr relays.
  """

  require Logger

  alias Rss2Nostr.Nostr.WebSocketHandler

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
    |> Enum.flat_map(fn url ->
      case query(url, filter, timeout) do
        {:ok, events} ->
          events

        {:error, reason} ->
          Logger.debug("Relay query failed for #{url}: #{inspect(reason)}")
          []
      end
    end)
    |> Enum.uniq_by(&event_id/1)
    |> Enum.reject(&is_nil(event_id(&1)))
  end

  @spec query(String.t(), map(), non_neg_integer()) :: {:ok, [map()]} | {:error, term()}
  def query(url, filter, timeout \\ @default_timeout)
      when is_binary(url) and is_map(filter) do
    parent = self()

    case WebSocketHandler.start_link(url, parent) do
      {:ok, conn} ->
        result = await_events(conn, filter, timeout)
        stop_conn(conn)
        result

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp await_events(conn, filter, timeout) do
    receive do
      {:websockex_connected, ^conn} ->
        sub = "q" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)

        case send_req(conn, sub, filter) do
          :ok -> collect(conn, sub, [], timeout)
          error -> error
        end

      {:websockex_disconnected, reason} ->
        {:error, reason}
    after
      timeout ->
        {:error, :timeout}
    end
  end

  defp collect(conn, sub, events, timeout) do
    receive do
      {:relay_message, message} ->
        case Jason.decode(message) do
          {:ok, ["EVENT", ^sub, event]} when is_map(event) ->
            collect(conn, sub, [event | events], timeout)

          {:ok, ["EOSE", ^sub]} ->
            send_close(conn, sub)
            {:ok, Enum.reverse(events)}

          {:ok, ["NOTICE", notice]} ->
            Logger.debug("Relay query notice: #{notice}")
            collect(conn, sub, events, timeout)

          _ ->
            collect(conn, sub, events, timeout)
        end

      {:websockex_disconnected, reason} ->
        if events == [], do: {:error, reason}, else: {:ok, Enum.reverse(events)}
    after
      timeout ->
        send_close(conn, sub)
        if events == [], do: {:error, :timeout}, else: {:ok, Enum.reverse(events)}
    end
  end

  defp send_req(conn, sub, filter) do
    WebSockex.send_frame(conn, {:text, Jason.encode!(["REQ", sub, filter])})
  end

  defp send_close(conn, sub) do
    _ = WebSockex.send_frame(conn, {:text, Jason.encode!(["CLOSE", sub])})
    :ok
  rescue
    _ -> :ok
  end

  defp stop_conn(conn) do
    Process.exit(conn, :normal)
  rescue
    _ -> :ok
  end

  defp event_id(%{"id" => id}) when is_binary(id), do: id
  defp event_id(%{id: id}) when is_binary(id), do: id
  defp event_id(_), do: nil
end
