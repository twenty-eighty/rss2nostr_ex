defmodule Rss2Nostr.Web.Views.PostsTest do
  use Rss2NostrWeb.ConnCase, async: false

  alias Rss2Nostr.Posts
  alias Rss2Nostr.Posts.Post
  alias Rss2Nostr.Sources

  def create_test_post do
    {:ok, source} =
      Sources.create_source(%{
        name: "View Test Source",
        url: "https://example.com/view-test-feed-#{System.unique_integer([:positive])}.xml",
        type: "rss",
        language: "en",
        active: true
      })

    url = "https://example.com/view-article-#{System.unique_integer([:positive])}"

    {:ok, post} =
      Posts.create_post(%{
        title: "View Test Article",
        source_url: url,
        source_url_hash: Post.generate_url_hash(url),
        source_html: "<p>Content</p>",
        status: Post.status_new(),
        source_id: source.id
      })

    {source, post}
  end

  describe "index" do
    test "returns HTML with posts list", %{conn: conn} do
      html = page(conn, "/posts")

      assert is_binary(html)
      assert html =~ "<html"
      assert html =~ "Posts"
      assert html =~ "Pending images"
    end

    test "shows status filter options", %{conn: conn} do
      html = page(conn, "/posts")

      assert html =~ "status" or html =~ "filter" or html =~ "All"
    end

    test "shows posts when they exist", %{conn: conn} do
      {_source, post} = create_test_post()

      html = page(conn, "/posts")

      assert html =~ post.title or html =~ "View Test Article"
    end

    test "handles page parameter", %{conn: conn} do
      html = page(conn, "/posts?page=2")

      assert is_binary(html)
    end

    test "handles status filter", %{conn: conn} do
      html = page(conn, "/posts?status=new")

      assert is_binary(html)
    end

    test "filters posts by source", %{conn: conn} do
      {source, post} = create_test_post()
      {_other, other_post} = create_test_post()

      {:ok, post} = Posts.update_post(post, %{title: "Source Filter Match"})
      {:ok, other_post} = Posts.update_post(other_post, %{title: "Other Source Article"})

      html = page(conn, "/posts?source_id=#{source.id}")

      assert html =~ "All sources"
      assert html =~ source.name
      assert html =~ ~s(value="#{source.id}")
      assert html =~ post.title
      refute html =~ other_post.title
    end

    test "keeps source_id on status filter links", %{conn: conn} do
      {source, _post} = create_test_post()

      html = page(conn, "/posts?source_id=#{source.id}&status=9")

      assert html =~ "source_id=#{source.id}"
      assert html =~ "status=9"
    end

    test "keeps the current filter on status links", %{conn: conn} do
      {source, _post} = create_test_post()

      html = page(conn, "/posts?status=2&source_id=#{source.id}&q=berlin&page=2")

      assert html =~ "source_id=#{source.id}"
      assert html =~ "status=2"
      assert html =~ "q=berlin"
    end

    test "puts publish selected and select-all above the table", %{conn: conn} do
      {_source, post} = create_test_post()

      {:ok, _} =
        Posts.update_post(post, %{status: Post.status_processed(), title: "Ready To Publish"})

      html = page(conn, "/posts")
      publish_at = :binary.match(html, "Publish selected")
      table_at = :binary.match(html, "<table")
      select_all_at = :binary.match(html, "select-all-posts")

      assert publish_at != :nomatch
      assert table_at != :nomatch
      assert select_all_at != :nomatch
      assert elem(publish_at, 0) < elem(table_at, 0)
      assert html =~ ~s(id="select-all-posts")
      assert html =~ ~s(name="post_ids[]" value="#{post.id}")
    end

    test "select-all includes every filtered staging post id", %{conn: conn} do
      {source, first} = create_test_post()

      {:ok, first} =
        Posts.update_post(first, %{status: Post.status_processed(), title: "Filtered Staging One"})

      url = "https://example.com/view-article-#{System.unique_integer([:positive])}"

      {:ok, second} =
        Posts.create_post(%{
          title: "Filtered Staging Two",
          source_url: url,
          source_url_hash: Post.generate_url_hash(url),
          source_html: "<p>Content</p>",
          status: Post.status_processed(),
          source_id: source.id
        })

      html = page(conn, "/posts?source_id=#{source.id}&status=2&page=1")

      assert html =~ ~s(name="post_ids[]" value="#{first.id}")
      assert html =~ ~s(name="post_ids[]" value="#{second.id}")
    end

    test "filters posts by search term", %{conn: conn} do
      {_source, post} = create_test_post()
      {_other, other_post} = create_test_post()

      {:ok, post} = Posts.update_post(post, %{title: "Unique Filter Phrase"})
      {:ok, other_post} = Posts.update_post(other_post, %{title: "Something Else Entirely"})

      html = page(conn, "/posts?q=#{URI.encode_www_form("Unique Filter")}")

      assert html =~ ~s(name="q")
      assert html =~ post.title
      refute html =~ other_post.title
    end

    test "keeps search term on status filter links", %{conn: conn} do
      html = page(conn, "/posts?q=berlin&status=2")

      assert html =~ "q=berlin"
      assert html =~ ~s(value="berlin")
    end

    test "lists pending-image posts when filtering by status 9", %{conn: conn} do
      {_source, post} = create_test_post()

      {:ok, post} =
        Posts.update_post(post, %{
          status: Post.status_pending_images(),
          title: "Pending Filter Article"
        })

      html = page(conn, "/posts?status=9")

      assert html =~ post.title
      assert html =~ "btn-active"
    end

    test "lets pending-image posts be selected for reprocess", %{conn: conn} do
      {_source, post} = create_test_post()

      {:ok, post} =
        Posts.update_post(post, %{
          status: Post.status_pending_images(),
          title: "Pending Selectable Article"
        })

      html = page(conn, "/posts?status=9")

      assert html =~ ~s(name="post_ids[]" value="#{post.id}")
      assert html =~ ~s(data-publishable="false")
      assert html =~ "Reprocess selected"
    end
  end

  describe "show" do
    test "returns HTML for specific post", %{conn: conn} do
      {_source, post} = create_test_post()

      html = page(conn, "/posts/#{post.id}")

      assert is_binary(html)
      assert html =~ post.title or html =~ "View Test Article"
      assert html =~ ~s(data-post-tab="event")
      assert html =~ "EVENT"
      assert html =~ "\"kind\""
      assert html =~ "\"tags\""
      assert html =~ "\"content\""
      refute html =~ "Encrypted wrap"
    end

    test "clears leftover pending error when images are already uploaded", %{conn: conn} do
      nostr = Application.get_env(:rss2nostr, :nostr, [])

      Application.put_env(
        :rss2nostr,
        :nostr,
        Keyword.put(nostr, :upload_endpoint, "https://route96.example")
      )

      on_exit(fn ->
        Application.put_env(:rss2nostr, :nostr, nostr)
      end)

      {_source, post} = create_test_post()
      uploaded = "https://route96.example/ready.jpg"

      {:ok, post} =
        Posts.update_post(post, %{
          status: Post.status_pending_images(),
          content: "![Hero](#{uploaded})",
          image: uploaded,
          last_error: "Images still need uploading"
        })

      {:ok, _} =
        Posts.create_image(%{
          post_id: post.id,
          original_url: "https://cdn.example/hero.jpg",
          uploaded_url: uploaded
        })

      html = page(conn, "/posts/#{post.id}")

      refute html =~ "Images still need uploading"
      refute html =~ "Upload images"
      assert html =~ "staging"
    end

    test "offers upload images when the post is pending images", %{conn: conn} do
      {source, post} = create_test_post()

      {:ok, post} =
        Posts.update_post(post, %{
          status: Post.status_pending_images(),
          content: "Body",
          image: "https://cdn.example/hero.jpg",
          last_error: "NOSTR_UPLOAD_ENDPOINT is not set"
        })

      html = page(conn, "/posts/#{post.id}")

      assert html =~ "pending images"
      assert html =~ "Upload images"
      assert html =~ "Reprocess"
      assert html =~ "Last error"
      assert html =~ source.name or html =~ "Images"
    end

    test "shows post details", %{conn: conn} do
      {source, post} = create_test_post()

      html = page(conn, "/posts/#{post.id}")

      assert html =~ post.title or html =~ source.name or html =~ "Status"
    end

    test "shows action buttons", %{conn: conn} do
      {_source, post} = create_test_post()

      html = page(conn, "/posts/#{post.id}")

      assert html =~ "process" or html =~ "Process" or html =~ "publish" or html =~ "Publish"
    end

    test "shows published hashtags without source exclusions", %{conn: conn} do
      {source, post} = create_test_post()

      {:ok, _} =
        Sources.update_source(source, %{excluded_hashtags: "ROOT, Haupteintrag"})

      {:ok, post} =
        Posts.update_post(post, %{
          status: Post.status_processed(),
          content: "Body",
          categories: ["Haupteintrag", "Politik", "ROOT", "radiomuenchen"]
        })

      html = page(conn, "/posts/#{post.id}")

      assert html =~ ~s(value="politik, radiomuenchen")
      refute html =~ ~s(value="Haupteintrag)
      assert html =~ "Omitted from the event: Haupteintrag, ROOT"
      assert html =~ "#politik, #radiomuenchen"
      refute html =~ "#root"
      refute html =~ "#haupteintrag"
    end

    test "shows an editor for staging posts", %{conn: conn} do
      {_source, post} = create_test_post()

      {:ok, post} =
        Posts.update_post(post, %{
          status: Post.status_processed(),
          content: "Hello **world**",
          summary: "A summary",
          categories: ["nostr"]
        })

      html = page(conn, "/posts/#{post.id}")

      assert html =~ "staging"
      assert html =~ ~s(name="title")
      assert html =~ ~s(name="hashtags")
      assert html =~ "Hello **world**"
      assert html =~ ~s(data-post-tab="preview")
      assert html =~ "Publish to"
      assert html =~ "Reprocess"
    end

    test "shows publish notes on a published post", %{conn: conn} do
      {_source, post} = create_test_post()

      {:ok, post} =
        Posts.update_post(post, %{
          status: Post.status_published(),
          content: "Done",
          last_error: "wss://client-test.pareto.town: could not resolve host"
        })

      html = page(conn, "/posts/#{post.id}")

      assert html =~ "Publish notes"
      assert html =~ "could not resolve host"
    end

    test "shows republish and revise for published posts", %{conn: conn} do
      {_source, post} = create_test_post()
      {:ok, post} = Posts.update_post(post, %{status: Post.status_published(), content: "Done"})

      html = page(conn, "/posts/#{post.id}")

      assert html =~ "Republish"
      assert html =~ "Revise"
      assert html =~ ~s(phx-click="revise")
    end

    test "backs to the source articles tab by default", %{conn: conn} do
      {source, post} = create_test_post()
      {:ok, post} = Posts.update_post(post, %{status: Post.status_processed(), content: "Body"})

      html = page(conn, "/posts/#{post.id}")

      assert html =~ ~s(href="/sources/#{source.id}?tab=articles")
      refute html =~ ~s(href="/posts" class="btn btn-secondary">Back to List)
    end

    test "backs to an explicit return_to path", %{conn: conn} do
      {_source, post} = create_test_post()
      {:ok, post} = Posts.update_post(post, %{status: Post.status_processed(), content: "Body"})

      html = page(conn, "/posts/#{post.id}?return_to=#{URI.encode_www_form("/posts?status=2")}")

      assert html =~ ~s(href="/posts?status=2")
      assert html =~ ~s(name="return_to" value="/posts?status=2")
    end

    test "ignores an external return_to", %{conn: conn} do
      {source, post} = create_test_post()
      {:ok, post} = Posts.update_post(post, %{status: Post.status_processed(), content: "Body"})

      html = page(conn, "/posts/#{post.id}?return_to=#{URI.encode_www_form("//evil.example/")}")

      assert html =~ ~s(href="/sources/#{source.id}?tab=articles")
      refute html =~ "evil.example"
    end
  end
end
