defmodule Rss2Nostr.Web.RouterTest do
  use Rss2NostrWeb.ConnCase, async: false

  describe "GET /" do
    test "returns dashboard page", %{conn: conn} do
      html = page(conn, "/")

      assert html =~ "Dashboard"
      assert html =~ "RSS2Nostr"
    end

    test "redirects to login when not authenticated", %{conn: conn} do
      conn = get(conn, "/")

      assert redirected_to(conn) == "/login?next=#{URI.encode_www_form("/")}"
    end
  end

  describe "GET /login" do
    test "returns the NIP-07 login page", %{conn: conn} do
      conn = get(conn, "/login")

      assert html_response(conn, 200) =~ "Login with Nostr"
      assert html_response(conn, 200) =~ "window.nostr"
    end

    test "redirects to dashboard when already logged in", %{conn: conn} do
      conn = conn |> authed_conn() |> get("/login")

      assert redirected_to(conn) == "/"
    end
  end

  describe "GET /sources" do
    test "returns sources page", %{conn: conn} do
      assert page(conn, "/sources") =~ "Sources"
    end
  end

  describe "GET /sources/new" do
    test "returns new source form", %{conn: conn} do
      html = page(conn, "/sources/new")

      assert html =~ "Add Source"
      assert html =~ "<form"
      assert html =~ "Find feeds"
    end
  end

  describe "GET /sources/:id" do
    test "redirects for a missing source", %{conn: conn} do
      conn = conn |> authed_conn() |> get("/sources/999999")

      assert redirected_to(conn) == "/sources"
    end
  end

  describe "POST /api/sources/compose-preview" do
    test "returns 422 without a feed URL", %{conn: conn} do
      conn = conn |> authed_conn() |> post("/api/sources/compose-preview", %{})

      assert conn.status == 422
      assert conn.resp_body =~ "Feed URL is required"
    end
  end

  describe "GET /posts" do
    test "returns posts page", %{conn: conn} do
      html = page(conn, "/posts")

      assert html =~ "Posts"
      assert html =~ "Publish selected"
    end

    test "accepts status filter", %{conn: conn} do
      conn = conn |> authed_conn() |> get("/posts?status=new")

      assert html_response(conn, 200)
    end

    test "accepts page parameter", %{conn: conn} do
      conn = conn |> authed_conn() |> get("/posts?page=2")

      assert html_response(conn, 200)
    end

    test "accepts source_id filter", %{conn: conn} do
      html = page(conn, "/posts?source_id=1")

      assert html =~ "All sources"
    end

    test "accepts search term filter", %{conn: conn} do
      html = page(conn, "/posts?q=climate")

      assert html =~ ~s(name="q")
      assert html =~ ~s(value="climate")
    end
  end

  describe "GET /scheduler" do
    test "returns scheduler page", %{conn: conn} do
      assert page(conn, "/scheduler") =~ "Scheduler"
    end
  end

  describe "GET /settings" do
    test "returns settings page", %{conn: conn} do
      html = page(conn, "/settings")

      assert html =~ "Settings"
      assert html =~ "Admin access"
      assert html =~ "DM relays"
      assert html =~ "NOSTR_RELAYS_INBOX"
    end
  end

  describe "GET /static/style.css" do
    test "returns CSS stylesheet without auth", %{conn: conn} do
      conn = get(conn, "/static/style.css")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["text/css; charset=utf-8"]
      assert conn.resp_body =~ ":root"
      assert conn.resp_body =~ "--primary"
      assert conn.resp_body =~ "prefers-color-scheme: dark"
    end
  end

  describe "GET /mcp" do
    test "allows loopback when MCP_ALLOW_LOOPBACK is enabled", %{conn: conn} do
      original = Application.get_env(:rss2nostr, :mcp)

      on_exit(fn ->
        Application.put_env(:rss2nostr, :mcp, original)
      end)

      Application.put_env(:rss2nostr, :mcp, allow_loopback: true, token: nil)

      conn = get(conn, "/mcp")

      refute conn.status == 302
      refute conn.status == 401
    end

    test "rejects loopback when token is unset and loopback is not allowed", %{conn: conn} do
      original = Application.get_env(:rss2nostr, :mcp)

      on_exit(fn ->
        Application.put_env(:rss2nostr, :mcp, original)
      end)

      Application.put_env(:rss2nostr, :mcp, allow_loopback: false, token: nil)

      conn = get(conn, "/mcp")
      assert conn.status == 401
    end

    test "requires a bearer token when MCP_TOKEN is set", %{conn: conn} do
      original = Application.get_env(:rss2nostr, :mcp)

      on_exit(fn ->
        Application.put_env(:rss2nostr, :mcp, original)
      end)

      Application.put_env(:rss2nostr, :mcp, token: "secret-token", allow_loopback: true)

      conn = get(conn, "/mcp")
      assert conn.status == 401
    end
  end

  describe "GET /api/status" do
    test "returns JSON status", %{conn: conn} do
      conn = conn |> authed_conn() |> get("/api/status")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["application/json; charset=utf-8"]

      body = Jason.decode!(conn.resp_body)
      assert Map.has_key?(body, "sources")
      assert Map.has_key?(body, "posts")
      assert Map.has_key?(body, "version")
    end

    test "returns 401 JSON when not authenticated", %{conn: conn} do
      conn = get(conn, "/api/status")

      assert conn.status == 401

      assert Jason.decode!(conn.resp_body) == %{
               "error" => "Session expired. Reload the page and sign in."
             }
    end
  end

  describe "GET /api/sources" do
    test "returns JSON sources list", %{conn: conn} do
      conn = conn |> authed_conn() |> get("/api/sources")

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert Map.has_key?(body, "sources")
      assert is_list(body["sources"])
    end
  end

  describe "POST /api/sources/discover" do
    test "returns 401 JSON when not authenticated", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/sources/discover", Jason.encode!(%{url: "https://example.com"}))

      assert conn.status == 401
    end

    test "returns 422 for an invalid URL", %{conn: conn} do
      conn =
        conn
        |> authed_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/api/sources/discover", Jason.encode!(%{url: "javascript:alert(1)"}))

      assert conn.status == 422
      assert Jason.decode!(conn.resp_body)["error"]
    end
  end

  describe "GET /api/posts" do
    test "returns JSON posts list", %{conn: conn} do
      conn = conn |> authed_conn() |> get("/api/posts")

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert Map.has_key?(body, "posts")
    end
  end

  describe "404 handling" do
    test "returns 404 for unknown routes", %{conn: conn} do
      conn = conn |> authed_conn() |> get("/unknown/path")

      assert conn.status == 404
      assert conn.resp_body =~ "404"
      assert conn.resp_body =~ "Not Found"
    end
  end
end
