defmodule Rss2Nostr.Nostr.PublisherTest do
  use Rss2Nostr.DataCase

  alias Rss2Nostr.Nostr.{Event, Publisher}
  alias Rss2Nostr.Posts
  alias Rss2Nostr.Posts.Post
  alias Rss2Nostr.Sources

  @hex "0000000000000000000000000000000000000000000000000000000000000001"
  @author "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"

  describe "preview_event/2" do
    test "builds an unsigned long-form EVENT message for a draft without a key" do
      preview =
        Publisher.preview_event(%{
          title: "Hello",
          content: "# Hello\n\nBody",
          summary: "A summary",
          image: "https://example.com/img.jpg",
          source_url: "https://example.com/hello",
          published_at: ~U[2024-01-15 12:00:00Z],
          type: 30024
        })

      event = preview.event
      assert event.kind == 30023
      assert event.content == "# Hello\n\nBody"
      assert event.pubkey == String.duplicate("0", 64)
      refute Map.has_key?(event, :id)
      refute Map.has_key?(event, :sig)
      refute preview.encrypted
      assert is_nil(preview.inner)
      assert ["title", "Hello"] in event.tags
      assert ["summary", "A summary"] in event.tags
      assert ["image", "https://example.com/img.jpg"] in event.tags
      assert ["published_at", "1705320000"] in event.tags
      assert ["r", "https://example.com/hello"] in event.tags
      assert preview.message == ["EVENT", event]
      assert preview.json =~ "\"EVENT\""
      assert preview.json =~ "\"kind\": 30023"
      assert preview.json =~ "\"content\":"
      refute preview.signed
      assert preview.relays == ["wss://nos.lol"]
    end

    test "uses the inner article kind and test relays for a setup draft source" do
      {:ok, source} =
        Sources.create_source(%{
          name: "Preview Source",
          url: "https://example.com/preview-#{System.unique_integer([:positive])}.xml",
          type: "rss",
          language: "en",
          publish_as: "draft",
          pubkey: @author
        })

      url = "https://example.com/preview-article-#{System.unique_integer([:positive])}"

      {:ok, post} =
        Posts.create_post(%{
          title: "Preview Article",
          content: "Article body",
          source_url: url,
          source_url_hash: Post.generate_url_hash(url),
          status: Post.status_processed(),
          type: source.default_post_kind,
          source_id: source.id
        })

      post = Posts.get_post(post.id, preload: [:source])
      preview = Publisher.preview_event(post)

      assert preview.event.kind == 30023
      assert preview.event.content == "Article body"
      refute preview.encrypted
      assert ["title", "Preview Article"] in preview.event.tags
      assert ["p", @author] in preview.event.tags
      assert preview.relays == ["wss://nos.lol"]
    end

    test "previews the inner article that will be NIP-44-encrypted" do
      original = Application.get_env(:rss2nostr, :nostr)

      on_exit(fn ->
        Application.put_env(:rss2nostr, :nostr, original)
      end)

      nostr = Application.get_env(:rss2nostr, :nostr, [])
      Application.put_env(:rss2nostr, :nostr, Keyword.put(nostr, :private_key, @hex))

      {:ok, source} =
        Sources.create_source(%{
          name: "Encrypted Draft Source",
          url: "https://example.com/enc-draft-#{System.unique_integer([:positive])}.xml",
          type: "rss",
          language: "en",
          publish_as: "draft",
          pubkey: @author
        })

      url = "https://example.com/enc-draft-#{System.unique_integer([:positive])}"

      {:ok, post} =
        Posts.create_post(%{
          title: "Secret Draft",
          content: "Hidden body",
          source_url: url,
          source_url_hash: Post.generate_url_hash(url),
          status: Post.status_processed(),
          type: 30024,
          language: "en",
          categories: ["Nostr", "#Bitcoin"],
          source_id: source.id
        })

      post = Posts.get_post(post.id, preload: [:source])
      preview = Publisher.preview_event(post)

      assert preview.draft
      refute preview.encrypted
      assert preview.event.kind == 30023
      assert preview.event.content == "Hidden body"
      assert ["p", @author] in preview.event.tags
      assert ["L", "ISO-639-1"] in preview.event.tags
      assert ["l", "en", "ISO-639-1"] in preview.event.tags
      assert ["t", "nostr"] in preview.event.tags
      assert ["t", "bitcoin"] in preview.event.tags
      assert ["r", url] in preview.event.tags
      assert length(preview.parts) == 1
    end

    test "splits an oversized draft so each part fits NIP-44" do
      {:ok, source} =
        Sources.create_source(%{
          name: "Split Draft Source",
          url: "https://example.com/split-draft-#{System.unique_integer([:positive])}.xml",
          type: "rss",
          language: "en",
          publish_as: "draft",
          pubkey: @author
        })

      body = String.duplicate("lorem ipsum dolor sit amet. ", 2500)

      content =
        Enum.map_join(1..6, "\n\n", fn n ->
          "## Section #{n}\n\n#{body}"
        end)

      url = "https://example.com/split-#{System.unique_integer([:positive])}"

      {:ok, post} =
        Posts.create_post(%{
          title: "Huge Draft",
          content: content,
          source_url: url,
          source_url_hash: Post.generate_url_hash(url),
          status: Post.status_processed(),
          type: 30024,
          source_id: source.id
        })

      post = Posts.get_post(post.id, preload: [:source])
      preview = Publisher.preview_event(post)
      max = Event.max_draft_plaintext_size()

      assert length(preview.parts) > 1
      assert ["title", "Huge Draft (1/#{length(preview.parts)})"] in preview.event.tags

      Enum.with_index(preview.parts, 1)
      |> Enum.each(fn {event, index} ->
        assert Event.draft_plaintext_size(event) <= max
        assert ["title", "Huge Draft (#{index}/#{length(preview.parts)})"] in event.tags
      end)
    end

    test "leaves articles as plaintext kind 30023" do
      {:ok, source} =
        Sources.create_source(%{
          name: "Article Source",
          url: "https://example.com/article-src-#{System.unique_integer([:positive])}.xml",
          type: "rss",
          language: "en",
          publish_as: "article",
          signing_nsec: @hex
        })

      url = "https://example.com/article-#{System.unique_integer([:positive])}"

      {:ok, post} =
        Posts.create_post(%{
          title: "Public Article",
          content: "Public body",
          source_url: url,
          source_url_hash: Post.generate_url_hash(url),
          status: Post.status_processed(),
          type: 30023,
          source_id: source.id
        })

      post = Posts.get_post(post.id, preload: [:source])
      preview = Publisher.preview_event(post)

      assert preview.event.kind == 30023
      assert preview.event.content == "Public body"
      refute preview.encrypted
      assert is_nil(preview.inner)
      refute Enum.any?(preview.event.tags, fn [tag | _] -> tag == "p" end)
    end
  end
end
