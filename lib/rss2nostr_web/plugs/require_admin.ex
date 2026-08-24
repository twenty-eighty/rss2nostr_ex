defmodule Rss2NostrWeb.Plugs.RequireAdmin do
  @moduledoc false

  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2]

  alias Rss2Nostr.Web.Auth

  def init(opts), do: opts

  def call(conn, _opts) do
    if Auth.logged_in?(conn) do
      Auth.put_current_pubkey(Auth.session_pubkey(conn))
      conn
    else
      conn
      |> redirect(to: login_path(conn))
      |> halt()
    end
  end

  defp login_path(%Plug.Conn{method: "GET", request_path: path} = conn)
       when path not in ["", "/login"] do
    next =
      case conn.query_string do
        "" -> path
        query -> path <> "?" <> query
      end

    "/login?next=" <> URI.encode_www_form(next)
  end

  defp login_path(_), do: "/login"
end
