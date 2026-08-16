defmodule Rss2Nostr.Nostr.DraftCleanupTest do
  use Rss2Nostr.DataCase

  alias Rss2Nostr.Nostr.DraftCleanup
  alias Rss2Nostr.Posts
  alias Rss2Nostr.Posts.Post
  alias Rss2Nostr.Sources

  @hex "0000000000000000000000000000000000000000000000000000000000000001"
  @author "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"

  setup do
    original = Application.get_env(:rss2nostr, :nostr)

    on_exit(fn ->
      Application.put_env(:rss2nostr, :nostr, original)
    end)

    nostr = Application.get_env(:rss2nostr, :nostr, [])
    Application.put_env(:rss2nostr, :nostr, Keyword.put(nostr, :private_key, @hex))
    :ok
  end

  test "skips published drafts until a kind 30023 exists" do
    post = published_draft()

    query = fn _urls, _filter -> [] end
    publish = fn _urls, _event -> flunk("should not publish") end

    assert {:ok, %{deleted: 0, skipped: 1}} =
             DraftCleanup.run(query: query, publish: publish, posts: [post])

    assert is_nil(Posts.get_post(post.id).draft_cleaned_at)
  end

  test "deletes our drafts when a kind 30023 with the same d tag exists" do
    post = published_draft()
    parent = self()

    query = fn _urls, filter ->
      kinds = filter["kinds"] || []

      if 30023 in kinds do
        [%{"id" => "article-event"}]
      else
        [%{"id" => "draft-event"}]
      end
    end

    publish = fn urls, event ->
      send(parent, {:deletion, urls, event})
      Enum.map(urls, &{&1, :ok})
    end

    assert {:ok, %{deleted: 1, skipped: 0}} =
             DraftCleanup.run(query: query, publish: publish, posts: [post])

    assert_received {:deletion, _urls, event}
    assert event.kind == 5
    assert ["e", "draft-event"] in event.tags
    assert ["e", "published-event"] in event.tags
    assert Enum.any?(event.tags, fn [tag | rest] -> tag == "a" and hd(rest) =~ "30024:" end)
    assert Enum.any?(event.tags, fn [tag | rest] -> tag == "a" and hd(rest) =~ "31234:" end)

    cleaned = Posts.get_post(post.id)
    assert cleaned.draft_cleaned_at
  end

  test "does not clean again after a successful deletion" do
    post = published_draft()

    query = fn _urls, filter ->
      if 30023 in (filter["kinds"] || []), do: [%{"id" => "article-event"}], else: []
    end

    publish = fn urls, _event -> Enum.map(urls, &{&1, :ok}) end

    assert {:ok, %{deleted: 1}} =
             DraftCleanup.run(query: query, publish: publish, posts: [post])

    assert {:ok, %{deleted: 0, skipped: 0}} =
             DraftCleanup.run(query: query, publish: publish, posts: [])
    assert Posts.get_post(post.id).draft_cleaned_at
  end

  defp published_draft do
    {:ok, source} =
      Sources.create_source(%{
        name: "Cleanup Source",
        url: "https://example.com/cleanup-#{System.unique_integer([:positive])}.xml",
        type: "rss",
        language: "en",
        publish_as: "draft",
        pubkey: @author
      })

    url = "https://example.com/raging-destruction"

    {:ok, post} =
      Posts.create_post(%{
        title: "Raging Destruction",
        content: "Body",
        source_url: url,
        source_url_hash: Post.generate_url_hash(url <> "-#{System.unique_integer([:positive])}"),
        status: Post.status_published(),
        type: 30024,
        event_id: "published-event",
        source_id: source.id
      })

    Posts.get_post(post.id, preload: [:source])
  end
end
