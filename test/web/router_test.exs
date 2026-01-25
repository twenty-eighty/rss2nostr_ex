defmodule Rss2Nostr.Web.RouterTest do
  use Rss2Nostr.DataCase, async: false
  import Plug.Test
  import Plug.Conn

  alias Rss2Nostr.Web.Router

  @opts Router.init([])

  describe "GET /" do
    test "returns dashboard page" do
      conn = conn(:get, "/")
      conn = Router.call(conn, @opts)

      assert conn.status == 200
      assert conn.resp_body =~ "Dashboard"
      assert conn.resp_body =~ "RSS2Nostr"
    end
  end

  describe "GET /sources" do
    test "returns sources page" do
      conn = conn(:get, "/sources")
      conn = Router.call(conn, @opts)

      assert conn.status == 200
      assert conn.resp_body =~ "Sources"
    end
  end

  describe "GET /sources/new" do
    test "returns new source form" do
      conn = conn(:get, "/sources/new")
      conn = Router.call(conn, @opts)

      assert conn.status == 200
      assert conn.resp_body =~ "Add Source"
      assert conn.resp_body =~ "<form"
    end
  end

  describe "GET /posts" do
    test "returns posts page" do
      conn = conn(:get, "/posts")
      conn = Router.call(conn, @opts)

      assert conn.status == 200
      assert conn.resp_body =~ "Posts"
    end

    test "accepts status filter" do
      conn = conn(:get, "/posts?status=new")
      conn = Router.call(conn, @opts)

      assert conn.status == 200
    end

    test "accepts page parameter" do
      conn = conn(:get, "/posts?page=2")
      conn = Router.call(conn, @opts)

      assert conn.status == 200
    end
  end

  describe "GET /scheduler" do
    test "returns scheduler page" do
      conn = conn(:get, "/scheduler")
      conn = Router.call(conn, @opts)

      assert conn.status == 200
      assert conn.resp_body =~ "Scheduler"
    end
  end

  describe "GET /settings" do
    test "returns settings page" do
      conn = conn(:get, "/settings")
      conn = Router.call(conn, @opts)

      assert conn.status == 200
      assert conn.resp_body =~ "Settings"
    end
  end

  describe "GET /static/style.css" do
    test "returns CSS stylesheet" do
      conn = conn(:get, "/static/style.css")
      conn = Router.call(conn, @opts)

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["text/css; charset=utf-8"]
      assert conn.resp_body =~ ":root"
      assert conn.resp_body =~ "--primary"
    end
  end

  describe "GET /api/status" do
    test "returns JSON status" do
      conn = conn(:get, "/api/status")
      conn = Router.call(conn, @opts)

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["application/json; charset=utf-8"]

      body = Jason.decode!(conn.resp_body)
      assert Map.has_key?(body, "sources")
      assert Map.has_key?(body, "posts")
      assert Map.has_key?(body, "version")
    end
  end

  describe "GET /api/sources" do
    test "returns JSON sources list" do
      conn = conn(:get, "/api/sources")
      conn = Router.call(conn, @opts)

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert Map.has_key?(body, "sources")
      assert is_list(body["sources"])
    end
  end

  describe "GET /api/posts" do
    test "returns JSON posts list" do
      conn = conn(:get, "/api/posts")
      conn = Router.call(conn, @opts)

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert Map.has_key?(body, "posts")
    end
  end

  describe "404 handling" do
    test "returns 404 for unknown routes" do
      conn = conn(:get, "/unknown/path")
      conn = Router.call(conn, @opts)

      assert conn.status == 404
      assert conn.resp_body =~ "404"
      assert conn.resp_body =~ "Not Found"
    end
  end
end
