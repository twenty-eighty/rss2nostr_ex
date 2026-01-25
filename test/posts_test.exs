defmodule Rss2Nostr.PostsTest do
  use Rss2Nostr.DataCase

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
      source_url: "https://example.com/article/1",
      source_url_hash: Post.generate_url_hash("https://example.com/article/1"),
      source_html: "<p>Content</p>",
      status: Post.status_new(),
      source_id: source_id
    }
  end

  setup do
    {:ok, source} = Sources.create_source(@source_attrs)
    %{source: source}
  end

  describe "list_posts/1" do
    test "returns all posts", %{source: source} do
      {:ok, post} = Posts.create_post(valid_post_attrs(source.id))
      posts = Posts.list_posts()

      assert Enum.any?(posts, fn p -> p.id == post.id end)
    end

    test "respects limit option", %{source: source} do
      for i <- 1..5 do
        attrs =
          valid_post_attrs(source.id)
          |> Map.put(:source_url, "https://example.com/article/#{i}")
          |> Map.put(:source_url_hash, Post.generate_url_hash("https://example.com/article/#{i}"))

        Posts.create_post(attrs)
      end

      posts = Posts.list_posts(limit: 3)
      assert length(posts) == 3
    end
  end

  describe "list_posts_by_status/2" do
    test "returns posts with matching status", %{source: source} do
      {:ok, new_post} = Posts.create_post(valid_post_attrs(source.id))

      {:ok, processed_post} =
        Posts.create_post(
          valid_post_attrs(source.id)
          |> Map.put(:source_url, "https://example.com/article/2")
          |> Map.put(:source_url_hash, Post.generate_url_hash("https://example.com/article/2"))
          |> Map.put(:status, Post.status_processed())
        )

      new_posts = Posts.list_posts_by_status(Post.status_new())
      processed_posts = Posts.list_posts_by_status(Post.status_processed())

      assert Enum.any?(new_posts, fn p -> p.id == new_post.id end)
      refute Enum.any?(new_posts, fn p -> p.id == processed_post.id end)

      assert Enum.any?(processed_posts, fn p -> p.id == processed_post.id end)
      refute Enum.any?(processed_posts, fn p -> p.id == new_post.id end)
    end
  end

  describe "list_new_posts/1" do
    test "returns only new posts", %{source: source} do
      {:ok, _} = Posts.create_post(valid_post_attrs(source.id))

      {:ok, _} =
        Posts.create_post(
          valid_post_attrs(source.id)
          |> Map.put(:source_url, "https://example.com/article/processed")
          |> Map.put(
            :source_url_hash,
            Post.generate_url_hash("https://example.com/article/processed")
          )
          |> Map.put(:status, Post.status_processed())
        )

      new_posts = Posts.list_new_posts()
      assert Enum.all?(new_posts, fn p -> p.status == Post.status_new() end)
    end
  end

  describe "get_post/1 and get_post!/1" do
    test "returns the post with given id", %{source: source} do
      {:ok, post} = Posts.create_post(valid_post_attrs(source.id))

      assert Posts.get_post(post.id).id == post.id
      assert Posts.get_post!(post.id).id == post.id
    end

    test "get_post returns nil for non-existent id" do
      assert Posts.get_post(-1) == nil
    end

    test "get_post! raises for non-existent id" do
      assert_raise Ecto.NoResultsError, fn ->
        Posts.get_post!(-1)
      end
    end
  end

  describe "create_post/1" do
    test "creates post with valid attrs", %{source: source} do
      {:ok, post} = Posts.create_post(valid_post_attrs(source.id))

      assert post.title == "Test Article"
      assert post.status == Post.status_new()
    end

    test "enforces unique source_url_hash", %{source: source} do
      attrs = valid_post_attrs(source.id)
      {:ok, _} = Posts.create_post(attrs)
      {:error, changeset} = Posts.create_post(attrs)

      assert changeset.errors[:source_url_hash]
    end
  end

  describe "update_post/2" do
    test "updates post with valid attrs", %{source: source} do
      {:ok, post} = Posts.create_post(valid_post_attrs(source.id))
      {:ok, updated} = Posts.update_post(post, %{title: "Updated Title"})

      assert updated.title == "Updated Title"
    end
  end

  describe "delete_post/1" do
    test "deletes the post", %{source: source} do
      {:ok, post} = Posts.create_post(valid_post_attrs(source.id))
      {:ok, _} = Posts.delete_post(post)

      assert Posts.get_post(post.id) == nil
    end
  end

  describe "status transitions" do
    test "mark_processing/1 sets status to processing", %{source: source} do
      {:ok, post} = Posts.create_post(valid_post_attrs(source.id))
      {:ok, updated} = Posts.mark_processing(post)

      assert updated.status == Post.status_processing()
    end

    test "mark_processed/1 sets status to processed", %{source: source} do
      {:ok, post} = Posts.create_post(valid_post_attrs(source.id))
      {:ok, updated} = Posts.mark_processed(post)

      assert updated.status == Post.status_processed()
    end

    test "mark_published/3 sets status and event info", %{source: source} do
      {:ok, post} = Posts.create_post(valid_post_attrs(source.id))
      event_id = "abc123"
      pubkey = "def456"
      naddr = "naddr1..."

      {:ok, updated} = Posts.mark_published(post, event_id, pubkey, naddr)

      assert updated.status == Post.status_published()
      assert updated.event_id == event_id
      assert updated.pubkey == pubkey
      assert updated.nostr_address == naddr
    end

    test "mark_error/2 sets status and error message", %{source: source} do
      {:ok, post} = Posts.create_post(valid_post_attrs(source.id))
      {:ok, updated} = Posts.mark_error(post, "Something went wrong")

      assert updated.status == Post.status_error()
      assert updated.last_error == "Something went wrong"
    end
  end

  describe "count functions" do
    test "count_posts/0 returns total count", %{source: source} do
      initial = Posts.count_posts()
      {:ok, _} = Posts.create_post(valid_post_attrs(source.id))

      assert Posts.count_posts() == initial + 1
    end

    test "count_posts_by_status/1 returns status-specific count", %{source: source} do
      {:ok, _} = Posts.create_post(valid_post_attrs(source.id))

      {:ok, _} =
        Posts.create_post(
          valid_post_attrs(source.id)
          |> Map.put(:source_url, "https://example.com/article/new2")
          |> Map.put(:source_url_hash, Post.generate_url_hash("https://example.com/article/new2"))
        )

      new_count = Posts.count_posts_by_status(Post.status_new())
      assert new_count >= 2
    end

    test "count_posts_by_status/1 accepts string status names", %{source: source} do
      {:ok, _} = Posts.create_post(valid_post_attrs(source.id))

      count = Posts.count_posts_by_status("new")
      assert count >= 1
    end
  end

  describe "exists_by_url_hash?/1" do
    test "returns true if post exists", %{source: source} do
      attrs = valid_post_attrs(source.id)
      {:ok, _} = Posts.create_post(attrs)

      assert Posts.exists_by_url_hash?(attrs.source_url_hash)
    end

    test "returns false if post doesn't exist" do
      refute Posts.exists_by_url_hash?("nonexistent_hash")
    end
  end
end
