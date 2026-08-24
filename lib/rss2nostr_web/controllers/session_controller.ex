defmodule Rss2NostrWeb.SessionController do
  @moduledoc false

  use Rss2NostrWeb, :controller

  alias Rss2Nostr.Web.Auth

  def new(conn, _params) do
    if Auth.logged_in?(conn) do
      redirect(conn, to: "/")
    else
      conn
      |> put_root_layout(false)
      |> put_layout(false)
      |> render(:new, configured?: Auth.configured?())
    end
  end

  def delete(conn, _params) do
    conn
    |> Auth.logout()
    |> redirect(to: "/login")
  end
end
