defmodule Rss2Nostr.MCP do
  @moduledoc """
  Starts the RSS2Nostr MCP server.

  * stdio — `mix rss2nostr.mcp` or `rss2nostr mcp` (Cursor / Claude Desktop)
  * HTTP — `/mcp` on the admin web server
  """

  @server_info %{name: "rss2nostr", version: "0.1.0"}

  @spec server_info() :: map()
  def server_info, do: @server_info

  @spec token() :: String.t() | nil
  def token do
    Application.get_env(:rss2nostr, :mcp, [])[:token]
  end

  @spec start_stdio() :: {:ok, pid()} | {:error, term()}
  def start_stdio do
    Rss2Nostr.MCP.Server.start_link(transport: :stdio)
  end
end
