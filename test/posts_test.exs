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

    test "filters by source_id", %{source: source} do
      {:ok, other} =
        Sources.create_source(%{
          name: "Other Source",
          url: "https://other.example/feed.xml",
          type: "rss",
          language: "en",
          active: true
        })

      {:ok, matching} = Posts.create_post(valid_post_attrs(source.id))

      {:ok, other_post} =
        Posts.create_post(
          valid_post_attrs(other.id)
          |> Map.put(:source_url, "https://other.example/article/1")
          |> Map.put(:source_url_hash, Post.generate_url_hash("https://other.example/article/1"))
        )

      posts = Posts.list_posts(source_id: source.id)

      assert Enum.any?(posts, fn p -> p.id == matching.id end)
      refute Enum.any?(posts, fn p -> p.id == other_post.id end)
    end

    test "filters by source_id and status together", %{source: source} do
      {:ok, new_post} = Posts.create_post(valid_post_attrs(source.id))

      {:ok, processed} =
        Posts.create_post(
          valid_post_attrs(source.id)
          |> Map.put(:source_url, "https://example.com/article/processed")
          |> Map.put(
            :source_url_hash,
            Post.generate_url_hash("https://example.com/article/processed")
          )
          |> Map.put(:status, Post.status_processed())
        )

      posts = Posts.list_posts(source_id: source.id, status: Post.status_new())

      assert Enum.any?(posts, fn p -> p.id == new_post.id end)
      refute Enum.any?(posts, fn p -> p.id == processed.id end)
    end

    test "filters by term in title or content", %{source: source} do
      {:ok, matching} =
        Posts.create_post(
          valid_post_attrs(source.id)
          |> Map.put(:title, "Climate report from Berlin")
        )

      {:ok, other} =
        Posts.create_post(
          valid_post_attrs(source.id)
          |> Map.put(:title, "Unrelated headline")
          |> Map.put(:content, "Body mentions climate once")
          |> Map.put(:source_url, "https://example.com/article/other")
          |> Map.put(
            :source_url_hash,
            Post.generate_url_hash("https://example.com/article/other")
          )
        )

      {:ok, miss} =
        Posts.create_post(
          valid_post_attrs(source.id)
          |> Map.put(:title, "Sports recap")
          |> Map.put(:content, "Scores and standings")
          |> Map.put(:source_url, "https://example.com/article/miss")
          |> Map.put(:source_url_hash, Post.generate_url_hash("https://example.com/article/miss"))
        )

      posts = Posts.list_posts(q: "climate")
      ids = Enum.map(posts, & &1.id)

      assert matching.id in ids
      assert other.id in ids
      refute miss.id in ids
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

    test "accepts numeric status query strings", %{source: source} do
      {:ok, pending} =
        Posts.create_post(
          valid_post_attrs(source.id)
          |> Map.put(:source_url, "https://example.com/article/pending")
          |> Map.put(
            :source_url_hash,
            Post.generate_url_hash("https://example.com/article/pending")
          )
          |> Map.put(:status, Post.status_pending_images())
        )

      pending_posts = Posts.list_posts_by_status("9")

      assert Enum.any?(pending_posts, fn p -> p.id == pending.id end)
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
      assert post.categories == []
    end

    test "enforces unique source_url_hash per source", %{source: source} do
      attrs = valid_post_attrs(source.id)
      {:ok, _} = Posts.create_post(attrs)
      {:error, changeset} = Posts.create_post(attrs)

      assert changeset.errors[:source_url_hash]
    end

    test "allows the same hash on a different source", %{source: source} do
      attrs = valid_post_attrs(source.id)
      {:ok, _} = Posts.create_post(attrs)

      {:ok, other} =
        Sources.create_source(%{
          name: "Other Hash Source",
          url: "https://other-hash.example/feed.xml",
          type: "rss",
          language: "en",
          active: true
        })

      assert {:ok, _} = Posts.create_post(Map.put(attrs, :source_id, other.id))
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

    test "mark_processed/1 sets status to staging and stamps staged_at", %{source: source} do
      {:ok, post} = Posts.create_post(valid_post_attrs(source.id))
      {:ok, updated} = Posts.mark_processed(post)

      assert updated.status == Post.status_processed()
      assert updated.staged_at
    end

    test "mark_pending_images/2 sets status so uploads can be finished", %{source: source} do
      {:ok, post} = Posts.create_post(valid_post_attrs(source.id))
      {:ok, updated} = Posts.mark_pending_images(post, "NOSTR_UPLOAD_ENDPOINT is not set")

      assert updated.status == Post.status_pending_images()
      assert updated.last_error == "NOSTR_UPLOAD_ENDPOINT is not set"
      assert Posts.list_pending_image_posts() |> Enum.any?(&(&1.id == updated.id))
    end

    test "mark_published/3 sets status and event info", %{source: source} do
      {:ok, post} = Posts.create_post(valid_post_attrs(source.id))
      {:ok, post} = Posts.update_post(post, %{last_error: "old publish issue"})
      event_id = "abc123"
      pubkey = "def456"
      naddr = "naddr1..."

      {:ok, updated} = Posts.mark_published(post, event_id, pubkey, naddr)

      assert updated.status == Post.status_published()
      assert updated.event_id == event_id
      assert updated.pubkey == pubkey
      assert updated.nostr_address == naddr
      assert is_nil(updated.last_error)
    end

    test "mark_published/3 stores an naddr longer than 255 characters", %{source: source} do
      {:ok, post} = Posts.create_post(valid_post_attrs(source.id))
      naddr = "naddr1" <> String.duplicate("a", 300)

      {:ok, updated} = Posts.mark_published(post, "abc123", "def456", naddr)

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

    test "source-scoped check ignores other sources and orphans", %{source: source} do
      attrs = valid_post_attrs(source.id)
      {:ok, _} = Posts.create_post(attrs)

      {:ok, other} =
        Sources.create_source(%{
          name: "Scoped Hash Source",
          url: "https://scoped-hash.example/feed.xml",
          type: "rss",
          language: "en",
          active: true
        })

      assert Posts.exists_by_url_hash?(attrs.source_url_hash, source.id)
      refute Posts.exists_by_url_hash?(attrs.source_url_hash, other.id)

      {:ok, orphan} =
        Posts.create_post(
          attrs
          |> Map.put(:source_id, nil)
          |> Map.put(:source_url, "https://example.com/article/orphan")
          |> Map.put(
            :source_url_hash,
            Post.generate_url_hash("https://example.com/article/orphan")
          )
        )

      refute Posts.exists_by_url_hash?(orphan.source_url_hash, source.id)
    end
  end

  describe "adopt_orphaned_by_url_hash/2" do
    test "reattaches a post whose source was deleted", %{source: source} do
      attrs = valid_post_attrs(source.id)
      {:ok, post} = Posts.create_post(Map.put(attrs, :source_id, nil))

      assert {:ok, adopted} = Posts.adopt_orphaned_by_url_hash(attrs.source_url_hash, source.id)
      assert adopted.id == post.id
      assert adopted.source_id == source.id
    end

    test "returns :none when no orphan exists", %{source: source} do
      attrs = valid_post_attrs(source.id)
      {:ok, _} = Posts.create_post(attrs)

      assert :none = Posts.adopt_orphaned_by_url_hash(attrs.source_url_hash, source.id)
    end
  end

  describe "staging" do
    @hex "0000000000000000000000000000000000000000000000000000000000000001"
    @pubkey "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"

    test "enter_staging stamps staged_at once and keeps it on re-entry", %{source: source} do
      {:ok, post} = Posts.create_post(valid_post_attrs(source.id))
      {:ok, staged} = Posts.enter_staging(post, notify: false)
      first = staged.staged_at

      assert staged.status == Post.status_processed()
      assert first

      {:ok, again} = Posts.enter_staging(staged, notify: false)
      assert again.staged_at == first
    end

    test "revise_to_staging restarts the hold", %{source: source} do
      earlier = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)

      {:ok, post} =
        Posts.create_post(
          valid_post_attrs(source.id)
          |> Map.put(:status, Post.status_published())
          |> Map.put(:staged_at, earlier)
        )

      {:ok, revised} = Posts.revise_to_staging(post)

      assert revised.status == Post.status_processed()
      assert DateTime.compare(revised.staged_at, earlier) == :gt
    end

    test "revise_to_staging rejects posts that are not published", %{source: source} do
      {:ok, post} = Posts.create_post(valid_post_attrs(source.id))
      assert {:error, :not_published} = Posts.revise_to_staging(post)
    end

    test "hold_elapsed?/1 is true when staged_at is nil or hold is 0", %{source: source} do
      {:ok, post} = Posts.create_post(valid_post_attrs(source.id))
      assert Posts.hold_elapsed?(post)

      {:ok, source} = Sources.update_source(source, %{staging_hold_minutes: 0})
      {:ok, staged} = Posts.enter_staging(post, notify: false)
      staged = %{staged | source: source}
      assert Posts.hold_elapsed?(staged)
    end

    test "hold_elapsed?/1 waits until staged_at plus hold", %{source: source} do
      {:ok, source} = Sources.update_source(source, %{staging_hold_minutes: 60})
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      staged_at = DateTime.add(now, -30, :minute)

      {:ok, post} =
        Posts.create_post(
          valid_post_attrs(source.id)
          |> Map.put(:status, Post.status_processed())
          |> Map.put(:staged_at, staged_at)
        )

      post = %{post | source: source}
      refute Posts.hold_elapsed?(post, now)
      assert Posts.hold_elapsed?(post, DateTime.add(now, 40, :minute))
    end

    test "list_exportable_posts/1 applies the hold and skips setup sources", %{source: source} do
      nostr = Application.get_env(:rss2nostr, :nostr, [])

      on_exit(fn ->
        Application.put_env(:rss2nostr, :nostr, nostr)
      end)

      Application.put_env(:rss2nostr, :nostr, Keyword.put(nostr, :private_key, @hex))

      {:ok, automated} =
        Sources.create_source(%{
          name: "Automated Export",
          url: "https://example.com/auto-#{System.unique_integer([:positive])}.xml",
          type: "rss",
          language: "en",
          pubkey: @pubkey,
          publish_as: "draft",
          mode: "automated",
          staging_hold_minutes: 60,
          active: true
        })

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, ready} =
        Posts.create_post(%{
          title: "Ready",
          source_url: "https://example.com/ready-#{System.unique_integer([:positive])}",
          source_url_hash: Post.generate_url_hash("ready-#{System.unique_integer([:positive])}"),
          status: Post.status_processed(),
          staged_at: DateTime.add(now, -90, :minute),
          source_id: automated.id
        })

      {:ok, held} =
        Posts.create_post(%{
          title: "Held",
          source_url: "https://example.com/held-#{System.unique_integer([:positive])}",
          source_url_hash: Post.generate_url_hash("held-#{System.unique_integer([:positive])}"),
          status: Post.status_processed(),
          staged_at: now,
          source_id: automated.id
        })

      {:ok, setup_post} =
        Posts.create_post(
          valid_post_attrs(source.id)
          |> Map.put(:status, Post.status_processed())
          |> Map.put(:staged_at, DateTime.add(now, -90, :minute))
        )

      ids = Enum.map(Posts.list_exportable_posts(limit: 50), & &1.id)

      assert ready.id in ids
      refute held.id in ids
      refute setup_post.id in ids
    end
  end
end
