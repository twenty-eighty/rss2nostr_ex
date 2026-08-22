defmodule Rss2Nostr.Web.Views.PostsTest do
  use Rss2Nostr.DataCase

  alias Rss2Nostr.Web.Views.Posts, as: PostsView
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

  describe "index/1" do
    test "returns HTML with posts list" do
      html = PostsView.index([])

      assert is_binary(html)
      assert html =~ "<html"
      assert html =~ "Posts"
      assert html =~ "Pending images"
    end

    test "shows status filter options" do
      html = PostsView.index([])

      # Should have filter options
      assert html =~ "status" or html =~ "filter" or html =~ "All"
    end

    test "shows posts when they exist" do
      {_source, post} = create_test_post()

      html = PostsView.index([])

      assert html =~ post.title or html =~ "View Test Article"
    end

    test "handles page parameter" do
      html = PostsView.index(page: 2)

      assert is_binary(html)
    end

    test "handles status filter" do
      html = PostsView.index(status: "new")

      assert is_binary(html)
    end

    test "filters posts by source" do
      {source, post} = create_test_post()
      {_other, other_post} = create_test_post()

      {:ok, post} = Posts.update_post(post, %{title: "Source Filter Match"})
      {:ok, other_post} = Posts.update_post(other_post, %{title: "Other Source Article"})

      html = PostsView.index(source_id: to_string(source.id))

      assert html =~ "All sources"
      assert html =~ source.name
      assert html =~ ~s(value="#{source.id}" selected)
      assert html =~ post.title
      refute html =~ other_post.title
    end

    test "keeps source_id on status filter links" do
      {source, _post} = create_test_post()

      html = PostsView.index(source_id: source.id, status: "9")

      assert html =~ "source_id=#{source.id}"
      assert html =~ ~s(name="status" value="9")
    end

    test "keeps the current filter on publish selected" do
      {source, _post} = create_test_post()

      html = PostsView.index(source_id: source.id, q: "berlin", status: "2", page: 2)

      assert html =~ ~s(name="return_to" value="/posts?status=2&amp;source_id=#{source.id}&amp;q=berlin&amp;page=2")
    end

    test "puts publish selected and select-all above the table" do
      {_source, post} = create_test_post()
      {:ok, _} = Posts.update_post(post, %{status: Post.status_processed(), title: "Ready To Publish"})

      html = PostsView.index([])
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

    test "select-all includes every filtered staging post id" do
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

      html = PostsView.index(source_id: source.id, status: "2", page: 1)

      assert html =~ ~s(name="post_ids[]" value="#{first.id}")
      assert html =~ ~s(name="post_ids[]" value="#{second.id}")
    end

    test "filters posts by search term" do
      {_source, post} = create_test_post()
      {_other, other_post} = create_test_post()

      {:ok, post} = Posts.update_post(post, %{title: "Unique Filter Phrase"})
      {:ok, other_post} = Posts.update_post(other_post, %{title: "Something Else Entirely"})

      html = PostsView.index(q: "Unique Filter")

      assert html =~ ~s(name="q")
      assert html =~ ~s(value="Unique Filter")
      assert html =~ post.title
      refute html =~ other_post.title
    end

    test "keeps search term on status filter links" do
      html = PostsView.index(q: "berlin", status: "2")

      assert html =~ "q=berlin"
      assert html =~ ~s(name="status" value="2")
      assert html =~ ~s(value="berlin")
    end

    test "lists pending-image posts when filtering by status 9" do
      {_source, post} = create_test_post()

      {:ok, post} =
        Posts.update_post(post, %{
          status: Post.status_pending_images(),
          title: "Pending Filter Article"
        })

      html = PostsView.index(status: "9")

      assert html =~ post.title
      assert html =~ "btn-active"
    end
  end

  describe "show/1" do
    test "returns HTML for specific post" do
      {_source, post} = create_test_post()

      html = PostsView.show(to_string(post.id))

      assert is_binary(html)
      assert html =~ post.title or html =~ "View Test Article"
      assert html =~ "data-post-tab=\"event\""
      assert html =~ "EVENT"
      assert html =~ "\"kind\""
      assert html =~ "\"tags\""
      assert html =~ "\"content\""
      refute html =~ "Encrypted wrap"
    end

    test "clears leftover pending error when images are already uploaded" do
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

      html = PostsView.show(to_string(post.id))

      refute html =~ "Images still need uploading"
      refute html =~ "Upload images"
      assert html =~ "staging"
    end

    test "offers upload images when the post is pending images" do
      {source, post} = create_test_post()

      {:ok, post} =
        Posts.update_post(post, %{
          status: Post.status_pending_images(),
          content: "Body",
          image: "https://cdn.example/hero.jpg",
          last_error: "NOSTR_UPLOAD_ENDPOINT is not set"
        })

      html = PostsView.show(to_string(post.id))

      assert html =~ "pending images"
      assert html =~ "Upload images"
      assert html =~ "Last error"
      assert html =~ source.name or html =~ "Images"
    end

    test "shows post details" do
      {source, post} = create_test_post()

      html = PostsView.show(to_string(post.id))

      # Should show post details
      assert html =~ post.title or html =~ source.name or html =~ "Status"
    end

    test "shows action buttons" do
      {_source, post} = create_test_post()

      html = PostsView.show(to_string(post.id))

      # Should have process/publish buttons
      assert html =~ "process" or html =~ "Process" or html =~ "publish" or html =~ "Publish"
    end

    test "shows published hashtags without source exclusions" do
      {source, post} = create_test_post()

      {:ok, _} =
        Sources.update_source(source, %{excluded_hashtags: "ROOT, Haupteintrag"})

      {:ok, post} =
        Posts.update_post(post, %{
          status: Post.status_processed(),
          content: "Body",
          categories: ["Haupteintrag", "Politik", "ROOT", "radiomuenchen"]
        })

      html = PostsView.show(to_string(post.id))

      assert html =~ ~s(value="politik, radiomuenchen")
      refute html =~ ~s(value="Haupteintrag)
      assert html =~ "Omitted from the event: Haupteintrag, ROOT"
      assert html =~ "#politik, #radiomuenchen"
      refute html =~ "#root"
      refute html =~ "#haupteintrag"
    end

    test "shows an editor for staging posts" do
      {_source, post} = create_test_post()

      {:ok, post} =
        Posts.update_post(post, %{
          status: Post.status_processed(),
          content: "Hello **world**",
          summary: "A summary",
          categories: ["nostr"]
        })

      html = PostsView.show(to_string(post.id))

      assert html =~ "staging"
      assert html =~ "name=\"title\""
      assert html =~ "name=\"hashtags\""
      assert html =~ "Hello **world**"
      assert html =~ "data-post-tab=\"preview\""
      assert html =~ "Publish to"
      assert html =~ "Reprocess"
      assert html =~ "/posts/#{post.id}/process"
    end

    test "shows publish notes on a published post" do
      {_source, post} = create_test_post()

      {:ok, post} =
        Posts.update_post(post, %{
          status: Post.status_published(),
          content: "Done",
          last_error: "wss://client-test.pareto.town: could not resolve host"
        })

      html = PostsView.show(to_string(post.id))

      assert html =~ "Publish notes"
      assert html =~ "could not resolve host"
    end

    test "shows republish and revise for published posts" do
      {_source, post} = create_test_post()
      {:ok, post} = Posts.update_post(post, %{status: Post.status_published(), content: "Done"})

      html = PostsView.show(to_string(post.id))

      assert html =~ "Republish"
      assert html =~ "Revise"
      assert html =~ "/posts/#{post.id}/revise"
    end

    test "backs to the source articles tab by default" do
      {source, post} = create_test_post()
      {:ok, post} = Posts.update_post(post, %{status: Post.status_processed(), content: "Body"})

      html = PostsView.show(to_string(post.id))

      assert html =~ ~s(href="/sources/#{source.id}?tab=articles")
      refute html =~ ~s(href="/posts" class="btn btn-secondary">Back to List)
    end

    test "backs to an explicit return_to path" do
      {_source, post} = create_test_post()
      {:ok, post} = Posts.update_post(post, %{status: Post.status_processed(), content: "Body"})

      html = PostsView.show(to_string(post.id), return_to: "/posts?status=2")

      assert html =~ ~s(href="/posts?status=2")
      assert html =~ ~s(name="return_to" value="/posts?status=2")
    end

    test "ignores an external return_to" do
      {source, post} = create_test_post()
      {:ok, post} = Posts.update_post(post, %{status: Post.status_processed(), content: "Body"})

      html = PostsView.show(to_string(post.id), return_to: "//evil.example/")

      assert html =~ ~s(href="/sources/#{source.id}?tab=articles")
      refute html =~ "evil.example"
    end
  end
end
