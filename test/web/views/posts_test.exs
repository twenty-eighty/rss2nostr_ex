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
  end

  describe "show/1" do
    test "returns HTML for specific post" do
      {_source, post} = create_test_post()

      html = PostsView.show(to_string(post.id))

      assert is_binary(html)
      assert html =~ post.title or html =~ "View Test Article"
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
  end
end
