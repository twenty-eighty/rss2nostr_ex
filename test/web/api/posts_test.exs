defmodule Rss2Nostr.Web.API.PostsTest do
  use Rss2Nostr.DataCase

  alias Rss2Nostr.Web.API.Posts, as: API
  alias Rss2Nostr.Posts
  alias Rss2Nostr.Posts.Post
  alias Rss2Nostr.Sources

  @source_attrs %{
    name: "Test Source",
    url: "https://example.com/feed.xml",
    type: "rss",
    language: "en",
    active: true
  }

  def valid_post_attrs(source_id) do
    %{
      title: "Test Article",
      source_url: "https://example.com/article/#{System.unique_integer([:positive])}",
      source_url_hash:
        Post.generate_url_hash(
          "https://example.com/article/#{System.unique_integer([:positive])}"
        ),
      source_html: "<p>Content</p>",
      status: Post.status_new(),
      source_id: source_id
    }
  end

  setup do
    {:ok, source} = Sources.create_source(@source_attrs)
    %{source: source}
  end

  describe "list/1" do
    test "returns empty list when no posts", %{source: _source} do
      result = API.list()

      assert %{posts: _, pagination: pagination} = result
      assert pagination.page == 1
      assert pagination.per_page == 20
    end

    test "returns posts with pagination", %{source: source} do
      for i <- 1..5 do
        url = "https://example.com/article/#{i}"

        attrs = %{
          title: "Article #{i}",
          source_url: url,
          source_url_hash: Post.generate_url_hash(url),
          source_html: "<p>Content #{i}</p>",
          status: Post.status_new(),
          source_id: source.id
        }

        Posts.create_post(attrs)
      end

      result = API.list(%{"page" => "1", "per_page" => "2"})

      assert length(result.posts) == 2
      assert result.pagination.total >= 5
      assert result.pagination.page == 1
      assert result.pagination.per_page == 2
    end

    test "filters by status", %{source: source} do
      # Create a new post
      url1 = "https://example.com/new-article"

      {:ok, _} =
        Posts.create_post(%{
          title: "New Article",
          source_url: url1,
          source_url_hash: Post.generate_url_hash(url1),
          source_html: "<p>Content</p>",
          status: Post.status_new(),
          source_id: source.id
        })

      # Create a processed post
      url2 = "https://example.com/processed-article"

      {:ok, _} =
        Posts.create_post(%{
          title: "Processed Article",
          source_url: url2,
          source_url_hash: Post.generate_url_hash(url2),
          source_html: "<p>Content</p>",
          status: Post.status_processed(),
          source_id: source.id
        })

      new_result = API.list(%{"status" => "new"})
      processed_result = API.list(%{"status" => "processed"})

      assert Enum.all?(new_result.posts, fn p -> p.status == "new" end)
      assert Enum.all?(processed_result.posts, fn p -> p.status == "staging" end)

      staging_result = API.list(%{"status" => "staging"})
      assert Enum.all?(staging_result.posts, fn p -> p.status == "staging" end)
    end

    test "handles invalid page parameter gracefully" do
      result = API.list(%{"page" => "invalid", "per_page" => "abc"})

      assert result.pagination.page == 1
      assert result.pagination.per_page == 20
    end
  end

  describe "get/1" do
    test "returns post when found", %{source: source} do
      url = "https://example.com/article/get-test"

      {:ok, post} =
        Posts.create_post(%{
          title: "Get Test Article",
          source_url: url,
          source_url_hash: Post.generate_url_hash(url),
          source_html: "<p>Content</p>",
          status: Post.status_new(),
          source_id: source.id
        })

      {:ok, result} = API.get(to_string(post.id))

      assert result.id == post.id
      assert result.title == "Get Test Article"
    end

    test "returns error for non-existent post" do
      assert {:error, :not_found} = API.get("999999")
    end

    test "returns error for invalid id" do
      assert {:error, :invalid_id} = API.get("invalid")
      assert {:error, :invalid_id} = API.get("-1")
      assert {:error, :invalid_id} = API.get("0")
    end
  end

  describe "process/1" do
    test "returns error for non-existent post" do
      assert {:error, :not_found} = API.process("999999")
    end

    test "returns error for invalid id" do
      assert {:error, :invalid_id} = API.process("invalid")
    end
  end

  describe "publish/1" do
    test "returns error for non-existent post" do
      assert {:error, :not_found} = API.publish("999999")
    end

    test "returns error for invalid id" do
      assert {:error, :invalid_id} = API.publish("invalid")
    end

    test "returns error when NOSTR_NSEC not configured", %{source: source} do
      url = "https://example.com/article/publish-test"

      {:ok, post} =
        Posts.create_post(%{
          title: "Publish Test Article",
          source_url: url,
          source_url_hash: Post.generate_url_hash(url),
          source_html: "<p>Content</p>",
          status: Post.status_processed(),
          source_id: source.id
        })

      # Ensure NOSTR_NSEC is not set
      System.delete_env("NOSTR_NSEC")

      assert {:error, "NOSTR_NSEC not configured"} = API.publish(to_string(post.id))
    end
  end

  describe "update/2" do
    test "edits a staging post", %{source: source} do
      url = "https://example.com/article/edit-test"

      {:ok, post} =
        Posts.create_post(%{
          title: "Old title",
          source_url: url,
          source_url_hash: Post.generate_url_hash(url),
          content: "old body",
          status: Post.status_processed(),
          source_id: source.id
        })

      {:ok, updated} =
        API.update(to_string(post.id), %{
          "title" => "New title",
          "summary" => "A summary",
          "hashtags" => "nostr, rss",
          "language" => "en",
          "content" => "new body"
        })

      assert updated.title == "New title"
      assert updated.summary == "A summary"
      assert updated.categories == ["nostr", "rss"]
      assert updated.language == "en"
      assert updated.content == "new body"
    end

    test "rejects edits on new posts", %{source: source} do
      {:ok, post} = Posts.create_post(valid_post_attrs(source.id))

      assert {:error, "Post cannot be edited in this status"} =
               API.update(to_string(post.id), %{"title" => "Nope"})
    end
  end

  describe "revise/1" do
    test "moves a published post to staging", %{source: source} do
      url = "https://example.com/article/revise-test"

      {:ok, post} =
        Posts.create_post(%{
          title: "Published",
          source_url: url,
          source_url_hash: Post.generate_url_hash(url),
          status: Post.status_published(),
          source_id: source.id
        })

      {:ok, revised} = API.revise(to_string(post.id))
      assert revised.status == Post.status_processed()
      assert revised.staged_at
    end

    test "reconverts markdown from stored HTML", %{source: source} do
      url = "https://example.com/article/revise-reconvert"

      {:ok, post} =
        Posts.create_post(%{
          title: "Published",
          source_url: url,
          source_url_hash: Post.generate_url_hash(url),
          source_html: "<p>This is <em>italic</em> next to <strong>Subscriber</strong>.</p>",
          content: "*italic* next to **Subscriber**.",
          status: Post.status_published(),
          source_id: source.id
        })

      {:ok, revised} = API.revise(to_string(post.id))

      assert revised.status == Post.status_processed()
      assert revised.content =~ "_italic_"
      refute revised.content =~ "*italic*"
    end

    test "rejects a post that is not published", %{source: source} do
      {:ok, post} = Posts.create_post(valid_post_attrs(source.id))
      assert {:error, "Only published articles can be revised"} = API.revise(to_string(post.id))
    end
  end

  describe "delete/1" do
    test "deletes existing post", %{source: source} do
      url = "https://example.com/article/delete-test"

      {:ok, post} =
        Posts.create_post(%{
          title: "Delete Test Article",
          source_url: url,
          source_url_hash: Post.generate_url_hash(url),
          source_html: "<p>Content</p>",
          status: Post.status_new(),
          source_id: source.id
        })

      {:ok, _} = API.delete(to_string(post.id))
      assert Posts.get_post(post.id) == nil
    end

    test "returns error for non-existent post" do
      assert {:error, :not_found} = API.delete("999999")
    end

    test "returns error for invalid id" do
      assert {:error, :invalid_id} = API.delete("invalid")
    end
  end

  describe "stats/0" do
    test "returns post statistics" do
      stats = API.stats()

      assert Map.has_key?(stats, :total)
      assert Map.has_key?(stats, :new)
      assert Map.has_key?(stats, :processing)
      assert Map.has_key?(stats, :processed)
      assert Map.has_key?(stats, :published)
      assert Map.has_key?(stats, :error)
    end
  end
end
