defmodule Rss2Nostr.Web.RouterExtendedTest do
  use Rss2Nostr.ConnCase, async: false

  alias Rss2Nostr.Sources
  alias Rss2Nostr.Posts
  alias Rss2Nostr.Posts.Post

  def unique_url do
    "https://example.com/feed-#{System.unique_integer([:positive])}.xml"
  end

  describe "POST /sources" do
    test "creates source with valid params" do
      conn =
        conn(:post, "/sources", %{
          "name" => "New Test Source",
          "url" => unique_url(),
          "type" => "rss",
          "language" => "en"
        })

      conn = call(conn)

      assert conn.status == 302
      [location] = get_resp_header(conn, "location")
      assert location =~ ~r"^/sources/\d+$"
    end

    test "returns 422 for invalid params" do
      conn = conn(:post, "/sources", %{"name" => "", "url" => ""})
      conn = call(conn)

      assert conn.status == 422
      assert conn.resp_body =~ "Add Source"
    end
  end

  describe "GET /sources/:id" do
    test "returns the compose page" do
      {:ok, source} =
        Sources.create_source(%{
          name: "Compose Route Source",
          url: unique_url(),
          type: "rss",
          language: "en"
        })

      conn = call(conn(:get, "/sources/#{source.id}"))

      assert conn.status == 200
      assert conn.resp_body =~ "Compose"
      assert conn.resp_body =~ source.name
      assert conn.resp_body =~ "source-tabs"
      assert conn.resp_body =~ "Nostr event preview"
    end
  end

  describe "POST /sources/:id/toggle" do
    test "toggles source status" do
      {:ok, source} =
        Sources.create_source(%{
          name: "Toggle Test",
          url: unique_url(),
          type: "rss",
          language: "en",
          active: true
        })

      conn = conn(:post, "/sources/#{source.id}/toggle")
      conn = call(conn)

      assert conn.status == 302
      assert get_resp_header(conn, "location") == ["/sources"]

      updated = Sources.get_source(source.id)
      assert updated.active == false
    end

    test "returns 404 for non-existent source" do
      conn = conn(:post, "/sources/999999/toggle")
      conn = call(conn)

      assert conn.status == 404
      assert conn.resp_body =~ "Not Found"
    end

    test "returns 400 for invalid id" do
      conn = conn(:post, "/sources/invalid/toggle")
      conn = call(conn)

      assert conn.status == 400
      assert conn.resp_body =~ "Bad Request"
    end
  end

  describe "POST /sources/:id/duplicate" do
    test "duplicates a source and opens the copy" do
      {:ok, source} =
        Sources.create_source(%{
          name: "Duplicate Test",
          url: unique_url(),
          type: "rss",
          language: "en",
          active: true
        })

      conn = conn(:post, "/sources/#{source.id}/duplicate")
      conn = call(conn)

      assert conn.status == 302
      [location] = get_resp_header(conn, "location")
      assert location =~ ~r"^/sources/\d+\?tab=feed"
      refute location =~ "/sources/#{source.id}?"

      copies = Sources.list_sources() |> Enum.reject(&(&1.id == source.id))
      assert Enum.any?(copies, &(&1.name == "Duplicate Test (copy)"))
    end

    test "returns 404 for a missing source" do
      conn = conn(:post, "/sources/999999/duplicate") |> call()
      assert conn.status == 404
    end
  end

  describe "POST /sources/:id/delete" do
    test "deletes existing source" do
      {:ok, source} =
        Sources.create_source(%{
          name: "Delete Test",
          url: unique_url(),
          type: "rss",
          language: "en",
          active: true
        })

      conn = conn(:post, "/sources/#{source.id}/delete")
      conn = call(conn)

      assert conn.status == 302
      assert Sources.get_source(source.id) == nil
    end

    test "returns 404 for non-existent source" do
      conn = conn(:post, "/sources/999999/delete")
      conn = call(conn)

      assert conn.status == 404
    end

    test "returns 400 for invalid id" do
      conn = conn(:post, "/sources/invalid/delete")
      conn = call(conn)

      assert conn.status == 400
    end
  end

  describe "GET /posts/:id" do
    setup do
      {:ok, source} =
        Sources.create_source(%{
          name: "Post Test Source",
          url: unique_url(),
          type: "rss",
          language: "en",
          active: true
        })

      url = "https://example.com/article/#{System.unique_integer([:positive])}"

      {:ok, post} =
        Posts.create_post(%{
          title: "Test Post",
          source_url: url,
          source_url_hash: Post.generate_url_hash(url),
          source_html: "<p>Content</p>",
          status: Post.status_new(),
          source_id: source.id
        })

      %{post: post, source: source}
    end

    test "returns post detail page", %{post: post} do
      conn = conn(:get, "/posts/#{post.id}")
      conn = call(conn)

      assert conn.status == 200
    end

    test "returns 404 for non-existent post" do
      conn = conn(:get, "/posts/999999")
      conn = call(conn)

      assert conn.status == 404
      assert conn.resp_body =~ "Not Found"
    end

    test "returns 400 for invalid post id" do
      conn = conn(:get, "/posts/invalid")
      conn = call(conn)

      assert conn.status == 400
      assert conn.resp_body =~ "Bad Request"
    end
  end

  describe "POST /posts/:id/process" do
    setup do
      {:ok, source} =
        Sources.create_source(%{
          name: "Process Test Source",
          url: unique_url(),
          type: "rss",
          language: "en",
          active: true
        })

      url = "https://example.com/article/process-#{System.unique_integer([:positive])}"

      {:ok, post} =
        Posts.create_post(%{
          title: "Process Test Post",
          source_url: url,
          source_url_hash: Post.generate_url_hash(url),
          source_html: "<p>Test content for processing</p>",
          status: Post.status_new(),
          source_id: source.id
        })

      %{post: post}
    end

    test "processes post and redirects", %{post: post} do
      conn = conn(:post, "/posts/#{post.id}/process")
      conn = call(conn)

      assert conn.status == 302
      assert get_resp_header(conn, "location") == ["/posts/#{post.id}"]
    end

    test "returns JSON when the client asks for it", %{post: post} do
      conn =
        conn(:post, "/posts/#{post.id}/process")
        |> put_req_header("accept", "application/json")

      conn = call(conn)

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["id"] == post.id
      assert is_integer(body["status"])
      assert is_binary(body["status_label"])
    end

    test "returns to the articles list when return_to is set", %{post: post} do
      conn =
        conn(:post, "/posts/#{post.id}/process", %{
          "return_to" => "/sources/33?tab=articles"
        })

      conn = call(conn)

      assert conn.status == 302
      assert get_resp_header(conn, "location") == ["/sources/33?tab=articles"]
    end

    test "ignores an external return_to", %{post: post} do
      conn = conn(:post, "/posts/#{post.id}/process", %{"return_to" => "https://evil.example/"})
      conn = call(conn)

      assert conn.status == 302
      assert get_resp_header(conn, "location") == ["/posts/#{post.id}"]
    end

    test "returns 404 for non-existent post" do
      conn = conn(:post, "/posts/999999/process")
      conn = call(conn)

      assert conn.status == 404
    end

    test "returns 400 for invalid post id" do
      conn = conn(:post, "/posts/invalid/process")
      conn = call(conn)

      assert conn.status == 400
    end
  end

  describe "POST /posts/:id/publish" do
    setup do
      {:ok, source} =
        Sources.create_source(%{
          name: "Publish Test Source",
          url: unique_url(),
          type: "rss",
          language: "en",
          active: true
        })

      url = "https://example.com/article/publish-#{System.unique_integer([:positive])}"

      {:ok, post} =
        Posts.create_post(%{
          title: "Publish Test Post",
          source_url: url,
          source_url_hash: Post.generate_url_hash(url),
          source_html: "<p>Content</p>",
          status: Post.status_processed(),
          source_id: source.id
        })

      %{post: post}
    end

    test "redirects after publish attempt", %{post: post} do
      conn = conn(:post, "/posts/#{post.id}/publish")
      conn = call(conn)

      # Should redirect even if publish fails (no NSEC configured)
      assert conn.status == 302
    end

    test "returns 404 for non-existent post" do
      conn = conn(:post, "/posts/999999/publish")
      conn = call(conn)

      assert conn.status == 404
    end

    test "returns 400 for invalid post id" do
      conn = conn(:post, "/posts/invalid/publish")
      conn = call(conn)

      assert conn.status == 400
    end
  end

  describe "POST /posts/publish-selected" do
    test "returns to the filtered posts list when return_to is set" do
      conn =
        conn(:post, "/posts/publish-selected", %{
          "return_to" => "/posts?source_id=32",
          "post_ids" => []
        })

      conn = call(conn)

      assert conn.status == 302
      [location] = get_resp_header(conn, "location")
      assert location =~ "/posts?source_id=32"
      assert location =~ "notice="
      assert location =~ "notice_kind=error"
    end

    test "ignores an external return_to" do
      conn =
        conn(:post, "/posts/publish-selected", %{
          "return_to" => "https://evil.example/",
          "post_ids" => []
        })

      conn = call(conn)

      assert conn.status == 302
      [location] = get_resp_header(conn, "location")
      assert location =~ ~r"^/posts\?"
      refute location =~ "evil.example"
    end
  end

  describe "GET /posts with pagination" do
    test "handles invalid page parameter" do
      conn = conn(:get, "/posts?page=invalid")
      conn = call(conn)

      assert conn.status == 200
    end

    test "handles negative page parameter" do
      conn = conn(:get, "/posts?page=-1")
      conn = call(conn)

      assert conn.status == 200
    end

    test "handles zero page parameter" do
      conn = conn(:get, "/posts?page=0")
      conn = call(conn)

      assert conn.status == 200
    end
  end

  describe "POST /scheduler routes" do
    test "POST /scheduler/start redirects" do
      conn = conn(:post, "/scheduler/start")
      conn = call(conn)

      assert conn.status == 302
      assert get_resp_header(conn, "location") == ["/scheduler"]
      assert Rss2Nostr.Scheduler.status().running

      on_exit(fn -> Rss2Nostr.Scheduler.stop() end)
    end

    test "POST /scheduler/stop redirects" do
      conn = conn(:post, "/scheduler/stop")
      conn = call(conn)

      assert conn.status == 302
      assert get_resp_header(conn, "location") == ["/scheduler"]
    end

    test "POST /scheduler/run/:task redirects" do
      conn = conn(:post, "/scheduler/run/import")
      conn = call(conn)

      assert conn.status == 302
      assert get_resp_header(conn, "location") == ["/scheduler"]
    end
  end

  describe "POST /settings" do
    test "updates settings and redirects" do
      conn = conn(:post, "/settings", %{"some_setting" => "value"})
      conn = call(conn)

      assert conn.status == 302
      assert get_resp_header(conn, "location") == ["/settings"]
    end
  end
end
