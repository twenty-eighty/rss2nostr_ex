defmodule Rss2Nostr.MCP.Http do
  @moduledoc false

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    ExMCP.HttpPlug.call(conn, ExMCP.HttpPlug.init(plug_opts()))
  end

  defp plug_opts do
    mcp = Application.get_env(:rss2nostr, :mcp, [])
    origins = Keyword.get(mcp, :cors_origins, [])
    hosts = Keyword.get(mcp, :allowed_hosts, :any)

    [
      handler: Rss2Nostr.MCP.Server,
      protocol_mode: :prefer_modern,
      server_info: Rss2Nostr.MCP.server_info(),
      handler_call_timeout: 60_000,
      cors_enabled: origins != [],
      allowed_origins: origins,
      allowed_hosts: hosts
    ]
  end
end
