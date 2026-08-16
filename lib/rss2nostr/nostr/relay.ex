defmodule Rss2Nostr.Nostr.Relay do
  @moduledoc """
  Handles WebSocket connections to Nostr relays for publishing events.
  Supports connection pooling, reconnection, and confirmation handling.
  """

  use GenServer
  require Logger

  alias Rss2Nostr.Nostr.WebSocketHandler

  defmodule State do
    @moduledoc false
    defstruct [
      :conn,
      :url,
      :status,
      :reconnect_attempts,
      :max_reconnect_attempts,
      :pending_requests,
      :pending_confirmations,
      :last_activity,
      :idle_timeout,
      :idle_timer
    ]
  end

  # Client API

  @doc """
  Starts a relay connection process.
  """
  def start_link(relay_url, opts \\ []) do
    name = Keyword.get(opts, :name, via_name(relay_url))
    GenServer.start_link(__MODULE__, relay_url, name: name)
  end

  @doc """
  Publishes an event to a specific relay.
  Returns :ok on success, {:error, reason} on failure.
  """
  def publish(relay_url, event, timeout \\ 15_000) do
    case get_or_start_relay(relay_url) do
      {:ok, pid} ->
        GenServer.call(pid, {:publish, event}, timeout)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Publishes an event to multiple relays concurrently.
  Returns a list of {relay_url, result} tuples.
  """
  def publish_to_relays(relay_urls, event, timeout \\ 10_000) do
    tasks =
      Enum.map(relay_urls, fn url ->
        task =
          Task.async(fn ->
            Process.flag(:trap_exit, true)

            try do
              publish(url, event, timeout)
            catch
              :exit, reason -> {:error, exit_reason(reason)}
            end
          end)

        {url, task}
      end)

    Enum.map(tasks, fn {url, task} ->
      case Task.yield(task, timeout + 1000) || Task.shutdown(task) do
        {:ok, result} -> {url, result}
        {:exit, reason} -> {url, {:error, exit_reason(reason)}}
        nil -> {url, {:error, :timeout}}
      end
    end)
  end

  @doc """
  Turns a relay or connection failure into a short message for the UI.
  """
  @spec format_error(term()) :: String.t()
  def format_error(%WebSockex.ConnError{original: original}), do: format_error(original)
  def format_error({:error, reason}), do: format_error(reason)
  def format_error(:nxdomain), do: "could not resolve host"
  def format_error(:econnrefused), do: "connection refused"
  def format_error(:timeout), do: "timed out"
  def format_error(:closed), do: "connection closed"
  def format_error(:disconnected), do: "disconnected"
  def format_error(:max_reconnect_attempts), do: "could not connect"
  def format_error(reason) when is_binary(reason) and reason != "", do: reason

  def format_error(reason) when is_atom(reason),
    do: reason |> Atom.to_string() |> String.replace("_", " ")

  def format_error(reason), do: inspect(reason)

  @doc """
  Closes the connection to a relay.
  """
  def disconnect(relay_url) do
    case Registry.lookup(Rss2Nostr.RelayRegistry, relay_url) do
      [{pid, _}] ->
        try do
          GenServer.stop(pid, :normal)
        catch
          :exit, _ -> :ok
        end

      [] ->
        :ok
    end
  end

  # GenServer callbacks

  @impl true
  def init(relay_url) do
    Process.flag(:trap_exit, true)

    state = %State{
      url: relay_url,
      status: :disconnected,
      reconnect_attempts: 0,
      max_reconnect_attempts: 5,
      pending_requests: [],
      pending_confirmations: %{},
      last_activity: nil,
      idle_timeout: 60_000,
      idle_timer: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:publish, event}, from, state) do
    case state.status do
      :connected ->
        case send_event(state.conn, event) do
          :ok ->
            event_id = get_event_id(event)
            new_confirmations = Map.put(state.pending_confirmations, event_id, from)

            new_state =
              %{state | pending_confirmations: new_confirmations}
              |> update_activity()
              |> schedule_idle_timeout()

            {:noreply, new_state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      :disconnected ->
        new_state =
          connect(%{state | pending_requests: [{:publish, event, from} | state.pending_requests]})

        {:noreply, new_state}

      :connecting ->
        {:noreply,
         %{state | pending_requests: [{:publish, event, from} | state.pending_requests]}}
    end
  end

  @impl true
  def handle_info({:websockex_connected, conn}, state) do
    Logger.info("Connected to relay #{state.url}")

    new_state =
      %{state | status: :connected, conn: conn, reconnect_attempts: 0}
      |> update_activity()
      |> schedule_idle_timeout()

    # Process pending requests
    final_state = process_pending_requests(new_state)
    {:noreply, final_state}
  end

  @impl true
  def handle_info({:websockex_disconnected, reason}, state) do
    Logger.info("Disconnected from relay #{state.url}: #{inspect(reason)}")
    {:noreply, handle_connection_lost(state, reason)}
  end

  @impl true
  def handle_info({:EXIT, pid, reason}, state) do
    if pid == state.conn or state.status == :connecting do
      {:noreply, handle_connection_lost(state, reason)}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:relay_message, message}, state) do
    new_state = handle_relay_message(message, state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:reconnect, state) do
    if state.pending_requests != [] do
      Logger.info("Reconnecting to #{state.url} - #{length(state.pending_requests)} pending")
      {:noreply, connect(state)}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:check_idle, state) do
    cond do
      state.status != :connected or is_nil(state.last_activity) ->
        {:noreply, %{state | idle_timer: nil}}

      idle_exceeded?(state) ->
        Logger.debug("Relay #{state.url} idle, closing connection")
        if state.conn, do: Process.exit(state.conn, :normal)
        {:noreply, %{state | status: :disconnected, conn: nil, idle_timer: nil}}

      true ->
        new_timer = Process.send_after(self(), :check_idle, state.idle_timeout)
        {:noreply, %{state | idle_timer: new_timer}}
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Relay #{state.url} received unknown message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private functions

  defp idle_exceeded?(state) do
    now = System.monotonic_time(:millisecond)
    now - state.last_activity > state.idle_timeout
  end

  defp via_name(relay_url) do
    {:via, Registry, {Rss2Nostr.RelayRegistry, relay_url}}
  end

  defp get_or_start_relay(relay_url) do
    case Registry.lookup(Rss2Nostr.RelayRegistry, relay_url) do
      [{pid, _}] ->
        if Process.alive?(pid), do: {:ok, pid}, else: start_relay(relay_url)

      [] ->
        start_relay(relay_url)
    end
  end

  defp start_relay(relay_url) do
    case GenServer.start(__MODULE__, relay_url, name: via_name(relay_url)) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      error -> error
    end
  end

  defp connect(state) do
    Logger.debug("Connecting to relay #{state.url}")

    case WebSocketHandler.start_link(state.url, self()) do
      {:ok, conn} ->
        %{state | conn: conn, status: :connecting}

      {:error, reason} ->
        Logger.error("Failed to connect to #{state.url}: #{inspect(reason)}")

        if fatal_connect_error?(reason) do
          fail_pending(state, exit_reason(reason))
        else
          schedule_reconnect(state)
        end
    end
  end

  defp send_event(conn, event) do
    message = Jason.encode!(["EVENT", event])
    Logger.debug("Sending to relay: #{message}")

    case WebSockex.send_frame(conn, {:text, message}) do
      :ok -> :ok
      error -> {:error, error}
    end
  rescue
    e ->
      Logger.error("Error sending event: #{inspect(e)}")
      {:error, e}
  end

  defp get_event_id(event) when is_map(event) do
    event["id"] || event[:id] || Map.get(event, "id") || Map.get(event, :id)
  end

  defp process_pending_requests(state) do
    Enum.reduce(state.pending_requests, %{state | pending_requests: []}, fn
      {:publish, event, from}, acc_state ->
        case send_event(acc_state.conn, event) do
          :ok ->
            event_id = get_event_id(event)
            new_confirmations = Map.put(acc_state.pending_confirmations, event_id, from)
            %{acc_state | pending_confirmations: new_confirmations}

          {:error, reason} ->
            GenServer.reply(from, {:error, reason})
            acc_state
        end
    end)
  end

  defp handle_relay_message(message, state) do
    case Jason.decode(message) do
      {:ok, ["OK", event_id, success, reason]} ->
        handle_ok_message(event_id, success, reason, state)

      {:ok, ["NOTICE", notice]} ->
        Logger.info("Relay notice from #{state.url}: #{notice}")
        state

      {:ok, other} ->
        Logger.debug("Relay #{state.url} message: #{inspect(other)}")
        state

      {:error, _} ->
        Logger.warning("Failed to parse relay message: #{message}")
        state
    end
  end

  defp handle_ok_message(event_id, success, reason, state) do
    case Map.pop(state.pending_confirmations, event_id) do
      {nil, _} ->
        Logger.warning("OK for unknown event #{event_id}")
        state

      {from, new_confirmations} ->
        if success do
          Logger.info("Event #{event_id} confirmed by #{state.url}")
          GenServer.reply(from, :ok)
        else
          Logger.warning("Event #{event_id} rejected by #{state.url}: #{reason}")
          GenServer.reply(from, {:error, reason})
        end

        %{state | pending_confirmations: new_confirmations}
        |> update_activity()
        |> schedule_idle_timeout()
    end
  end

  defp handle_connection_lost(state, reason) do
    if fatal_connect_error?(reason) do
      Logger.warning("Relay #{state.url} connection failed: #{inspect(reason)}")
      fail_pending(state, exit_reason(reason))
    else
      handle_disconnect(state)
    end
  end

  defp fail_pending(state, reason) do
    if state.idle_timer, do: Process.cancel_timer(state.idle_timer)

    Enum.each(state.pending_confirmations, fn {_event_id, from} ->
      GenServer.reply(from, {:error, reason})
    end)

    Enum.each(state.pending_requests, fn {:publish, _event, from} ->
      GenServer.reply(from, {:error, reason})
    end)

    %{
      state
      | status: :disconnected,
        conn: nil,
        idle_timer: nil,
        pending_requests: [],
        pending_confirmations: %{},
        reconnect_attempts: 0
    }
  end

  defp fatal_connect_error?(%WebSockex.ConnError{}), do: true
  defp fatal_connect_error?({:error, reason}), do: fatal_connect_error?(reason)
  defp fatal_connect_error?(%{reason: reason}), do: fatal_connect_error?(reason)
  defp fatal_connect_error?(:nxdomain), do: true
  defp fatal_connect_error?(_), do: false

  defp exit_reason({:error, reason}), do: exit_reason(reason)
  defp exit_reason(reason), do: reason

  defp handle_disconnect(state) do
    if state.idle_timer, do: Process.cancel_timer(state.idle_timer)

    new_state = %{state | status: :disconnected, conn: nil, idle_timer: nil}

    # Fail pending confirmations
    Enum.each(state.pending_confirmations, fn {_event_id, from} ->
      GenServer.reply(from, {:error, :disconnected})
    end)

    new_state = %{new_state | pending_confirmations: %{}}

    if state.pending_requests != [] do
      schedule_reconnect(new_state)
    else
      new_state
    end
  end

  defp schedule_reconnect(state) do
    if state.reconnect_attempts < state.max_reconnect_attempts do
      delay = round(:math.pow(2, state.reconnect_attempts) * 1000)
      Logger.info("Scheduling reconnect to #{state.url} in #{delay}ms")
      Process.send_after(self(), :reconnect, delay)
      %{state | reconnect_attempts: state.reconnect_attempts + 1}
    else
      Logger.error("Max reconnect attempts reached for #{state.url}")

      # Fail pending requests
      Enum.each(state.pending_requests, fn {:publish, _event, from} ->
        GenServer.reply(from, {:error, :max_reconnect_attempts})
      end)

      %{state | pending_requests: [], reconnect_attempts: 0}
    end
  end

  defp update_activity(state) do
    %{state | last_activity: System.monotonic_time(:millisecond)}
  end

  defp schedule_idle_timeout(state) do
    if state.idle_timer, do: Process.cancel_timer(state.idle_timer)

    if state.status == :connected do
      new_timer = Process.send_after(self(), :check_idle, state.idle_timeout)
      %{state | idle_timer: new_timer}
    else
      %{state | idle_timer: nil}
    end
  end
end
