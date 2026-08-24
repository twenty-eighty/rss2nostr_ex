defmodule Rss2NostrWeb.HomeLiveTest do
  use Rss2NostrWeb.ConnCase, async: false

  describe "GET /login" do
    test "renders the NIP-07 login page when not authenticated", %{conn: conn} do
      conn = get(conn, "/login")

      assert html_response(conn, 200) =~ "Login with Nostr"
      assert html_response(conn, 200) =~ "window.nostr"
    end

    test "redirects to the dashboard when already logged in", %{conn: conn} do
      conn = conn |> authed_conn() |> get("/login")

      assert redirected_to(conn) == "/"
    end
  end

  describe "dashboard" do
    test "GET / is the LiveView dashboard", %{conn: conn} do
      conn = conn |> authed_conn() |> get("/")

      assert html_response(conn, 200) =~ "Dashboard"
      assert html_response(conn, 200) =~ "data-phx-main"
    end
  end
end
