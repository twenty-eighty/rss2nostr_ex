defmodule Rss2Nostr.Web.RouterTest do
  use Rss2Nostr.ConnCase, async: false

  describe "GET /" do
    test "returns dashboard page" do
      conn = call(conn(:get, "/"))

      assert conn.status == 200
      assert conn.resp_body =~ "Dashboard"
      assert conn.resp_body =~ "RSS2Nostr"
    end

    test "redirects to login when not authenticated" do
      conn = call(conn(:get, "/"), auth: false)

      assert conn.status == 302
      assert get_resp_header(conn, "location") == ["/login?next=%2F"]
    end
  end

  describe "GET /login" do
    test "returns the NIP-07 login page" do
      conn = call(conn(:get, "/login"), auth: false)

      assert conn.status == 200
      assert conn.resp_body =~ "Login with Nostr"
      assert conn.resp_body =~ "window.nostr"
    end

    test "redirects to dashboard when already logged in" do
      conn = call(conn(:get, "/login"))

      assert conn.status == 302
      assert get_resp_header(conn, "location") == ["/"]
    end
  end

  describe "GET /sources" do
    test "returns sources page" do
      conn = call(conn(:get, "/sources"))

      assert conn.status == 200
      assert conn.resp_body =~ "Sources"
    end
  end

  describe "GET /sources/new" do
    test "returns new source form" do
      conn = call(conn(:get, "/sources/new"))

      assert conn.status == 200
      assert conn.resp_body =~ "Add Source"
      assert conn.resp_body =~ "<form"
      assert conn.resp_body =~ "Find feeds"
    end
  end

  describe "GET /sources/:id" do
    test "returns 404 for a missing source" do
      conn = call(conn(:get, "/sources/999999"))

      assert conn.status == 404
    end
  end

  describe "POST /api/sources/compose-preview" do
    test "returns 422 without a feed URL" do
      conn = call(conn(:post, "/api/sources/compose-preview", %{}))

      assert conn.status == 422
      assert conn.resp_body =~ "Feed URL is required"
    end
  end

  describe "GET /posts" do
    test "returns posts page" do
      conn = call(conn(:get, "/posts"))

      assert conn.status == 200
      assert conn.resp_body =~ "Posts"
      assert conn.resp_body =~ "Publish selected"
    end

    test "accepts status filter" do
      conn = call(conn(:get, "/posts?status=new"))

      assert conn.status == 200
    end

    test "accepts page parameter" do
      conn = call(conn(:get, "/posts?page=2"))

      assert conn.status == 200
    end

    test "accepts source_id filter" do
      conn = call(conn(:get, "/posts?source_id=1"))

      assert conn.status == 200
      assert conn.resp_body =~ "All sources"
    end

    test "accepts search term filter" do
      conn = call(conn(:get, "/posts?q=climate"))

      assert conn.status == 200
      assert conn.resp_body =~ ~s(name="q")
      assert conn.resp_body =~ ~s(value="climate")
    end
  end

  describe "GET /scheduler" do
    test "returns scheduler page" do
      conn = call(conn(:get, "/scheduler"))

      assert conn.status == 200
      assert conn.resp_body =~ "Scheduler"
    end
  end

  describe "GET /settings" do
    test "returns settings page" do
      conn = call(conn(:get, "/settings"))

      assert conn.status == 200
      assert conn.resp_body =~ "Settings"
      assert conn.resp_body =~ "Admin access"
      assert conn.resp_body =~ "DM relays"
      assert conn.resp_body =~ "NOSTR_RELAYS_INBOX"
    end
  end

  describe "GET /static/style.css" do
    test "returns CSS stylesheet without auth" do
      conn = call(conn(:get, "/static/style.css"), auth: false)

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["text/css; charset=utf-8"]
      assert conn.resp_body =~ ":root"
      assert conn.resp_body =~ "--primary"
      assert conn.resp_body =~ "prefers-color-scheme: dark"
    end
  end

  describe "GET /mcp" do
    test "does not redirect loopback clients to login" do
      conn = call(conn(:get, "/mcp"), auth: false)

      refute conn.status == 302
      refute conn.status == 401
    end

    test "requires a bearer token when MCP_TOKEN is set" do
      original = Application.get_env(:rss2nostr, :mcp)

      on_exit(fn ->
        Application.put_env(:rss2nostr, :mcp, original)
      end)

      Application.put_env(:rss2nostr, :mcp, token: "secret-token")

      conn = call(conn(:get, "/mcp"), auth: false)
      assert conn.status == 401
    end
  end

  describe "GET /api/status" do
    test "returns JSON status" do
      conn = call(conn(:get, "/api/status"))

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["application/json; charset=utf-8"]

      body = Jason.decode!(conn.resp_body)
      assert Map.has_key?(body, "sources")
      assert Map.has_key?(body, "posts")
      assert Map.has_key?(body, "version")
    end

    test "returns 401 JSON when not authenticated" do
      conn = call(conn(:get, "/api/status"), auth: false)

      assert conn.status == 401
      assert Jason.decode!(conn.resp_body) == %{"error" => "unauthorized"}
    end
  end

  describe "GET /api/sources" do
    test "returns JSON sources list" do
      conn = call(conn(:get, "/api/sources"))

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert Map.has_key?(body, "sources")
      assert is_list(body["sources"])
    end
  end

  describe "POST /api/sources/discover" do
    test "returns 401 JSON when not authenticated" do
      conn =
        call(conn(:post, "/api/sources/discover", Jason.encode!(%{url: "https://example.com"})),
          auth: false
        )

      assert conn.status == 401
    end

    test "returns 422 for an invalid URL" do
      conn =
        conn(:post, "/api/sources/discover", Jason.encode!(%{url: "javascript:alert(1)"}))
        |> put_req_header("content-type", "application/json")
        |> call()

      assert conn.status == 422
      assert Jason.decode!(conn.resp_body)["error"]
    end
  end

  describe "GET /api/posts" do
    test "returns JSON posts list" do
      conn = call(conn(:get, "/api/posts"))

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert Map.has_key?(body, "posts")
    end
  end

  describe "404 handling" do
    test "returns 404 for unknown routes" do
      conn = call(conn(:get, "/unknown/path"))

      assert conn.status == 404
      assert conn.resp_body =~ "404"
      assert conn.resp_body =~ "Not Found"
    end
  end
end
