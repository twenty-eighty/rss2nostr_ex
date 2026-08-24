defmodule Rss2NostrWeb.Endpoint do
  @moduledoc false

  use Phoenix.Endpoint, otp_app: :rss2nostr

  @session_options Rss2Nostr.Web.Auth.session_opts()

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [:uri, session: @session_options]],
    longpoll: [connect_info: [:uri, session: @session_options]]

  plug Plug.Static,
    at: "/",
    from: :rss2nostr,
    gzip: false,
    only: Rss2NostrWeb.static_paths()

  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]
  plug :maybe_parse
  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug Rss2NostrWeb.Router

  @parser_opts Plug.Parsers.init(
                 parsers: [:urlencoded, :multipart, :json],
                 pass: ["*/*"],
                 json_decoder: Jason
               )

  # ExMCP reads the raw body. Skip parsers for /mcp, matching the Plug router.
  @spec maybe_parse(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  defp maybe_parse(%Plug.Conn{path_info: ["mcp" | _]} = conn, _opts), do: conn
  defp maybe_parse(conn, _opts), do: Plug.Parsers.call(conn, @parser_opts)
end
