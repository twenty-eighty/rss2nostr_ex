defmodule Rss2Nostr.MCP do
  @moduledoc """
  Starts the RSS2Nostr MCP server.

  * stdio — `mix rss2nostr.mcp` or `rss2nostr mcp` (Cursor / Claude Desktop)
  * HTTP — `/mcp` on the admin web server
  """

  @server_info %{name: "rss2nostr", version: "0.1.0"}

  @type server_info :: %{name: String.t(), version: String.t()}

  @spec server_info() :: server_info()
  def server_info, do: @server_info

  @spec token() :: String.t() | nil
  def token do
    case Application.get_env(:rss2nostr, :mcp, [])[:token] do
      token when is_binary(token) and token != "" -> token
      _ -> nil
    end
  end

  @doc """
  When true and `MCP_TOKEN` is unset, loopback HTTP clients may use `/mcp`
  without a bearer token. Disabled by default because reverse proxies make
  every client look like 127.0.0.1.
  """
  @spec allow_loopback?() :: boolean()
  def allow_loopback? do
    Application.get_env(:rss2nostr, :mcp, [])[:allow_loopback] == true
  end

  @spec start_stdio() :: GenServer.on_start()
  def start_stdio do
    Rss2Nostr.MCP.Server.start_link(transport: :stdio)
  end
end
