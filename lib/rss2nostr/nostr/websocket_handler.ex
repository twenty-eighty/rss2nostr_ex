defmodule Rss2Nostr.Nostr.WebSocketHandler do
  @moduledoc """
  WebSockex handler for Nostr relay connections.
  """

  use WebSockex
  require Logger

  @spec start_link(String.t(), pid()) :: {:ok, pid()} | {:error, term()}
  def start_link(url, parent_pid) do
    WebSockex.start_link(url, __MODULE__, {parent_pid, url}, async: true)
  end

  @impl true
  @spec handle_connect(WebSockex.Conn.t(), {pid(), String.t()}) :: {:ok, {pid(), String.t()}}
  def handle_connect(_conn, {parent_pid, url}) do
    Logger.debug("WebSocket connected to #{url}")
    send(parent_pid, {:websockex_connected, self()})
    {:ok, {parent_pid, url}}
  end

  @impl true
  @spec handle_frame(WebSockex.Frame.frame(), {pid(), String.t()}) :: {:ok, {pid(), String.t()}}
  def handle_frame({:text, message}, state) do
    Logger.debug("WebSocket received: #{message}")
    send(elem(state, 0), {:relay_message, message})
    {:ok, state}
  end

  @impl true
  def handle_frame({:binary, data}, state) do
    Logger.debug("WebSocket received binary: #{inspect(data)}")
    {:ok, state}
  end

  @impl true
  def handle_frame(frame, state) do
    Logger.warning("Unhandled WebSocket frame: #{inspect(frame)}")
    {:ok, state}
  end

  @impl true
  @spec handle_disconnect(term(), {pid(), String.t()}) :: {:ok, {pid(), String.t()}}
  def handle_disconnect(connection_status, {parent_pid, url}) do
    Logger.info("WebSocket disconnected from #{url}: #{inspect(connection_status)}")
    send(parent_pid, {:websockex_disconnected, connection_status})
    {:ok, {parent_pid, url}}
  end

  @impl true
  @spec terminate(term(), {pid(), String.t()}) :: :ok
  def terminate(reason, {_parent_pid, url}) do
    Logger.debug("WebSocket terminating for #{url}: #{inspect(reason)}")
    :ok
  end
end
