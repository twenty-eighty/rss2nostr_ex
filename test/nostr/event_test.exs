defmodule Rss2Nostr.Nostr.EventTest do
  use ExUnit.Case, async: true

  alias Rss2Nostr.Nostr.Event

  @test_pubkey "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"

  describe "kind constants" do
    test "kind_long_form returns 30023" do
      assert Event.kind_long_form() == 30023
    end

    test "kind_long_form_draft returns 30024" do
      assert Event.kind_long_form_draft() == 30024
    end

    test "kind_draft_wrap returns 31234" do
      assert Event.kind_draft_wrap() == 31234
    end

    test "kind_deletion returns 5" do
      assert Event.kind_deletion() == 5
    end
  end

  describe "build_deletion/2" do
    test "adds e and a tags" do
      event =
        Event.build_deletion(@test_pubkey,
          event_ids: ["abc"],
          addresses: ["30024:#{@test_pubkey}:slug"],
          reason: "replaced by published article"
        )

      assert event.kind == 5
      assert ["e", "abc"] in event.tags
      assert ["a", "30024:#{@test_pubkey}:slug"] in event.tags
      assert event.content == "replaced by published article"
    end
  end

  describe "build_long_form/3" do
    test "builds event with required fields" do
      event =
        Event.build_long_form(@test_pubkey, "# Test Article\n\nContent here.",
          title: "Test Title"
        )

      assert event.pubkey == @test_pubkey
      assert event.kind == 30023
      assert event.content == "# Test Article\n\nContent here."
      assert is_integer(event.created_at)
      assert is_list(event.tags)
    end

    test "can build a draft kind 30024 event" do
      event = Event.build_long_form(@test_pubkey, "Content", title: "Draft", kind: 30024)
      assert event.kind == 30024
    end

    test "adds a p tag with the intended author on drafts" do
      author = "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"

      event =
        Event.build_long_form(@test_pubkey, "Content",
          title: "Draft",
          kind: 30024,
          author_pubkey: author
        )

      assert ["p", author] in event.tags
    end

    test "does not add a p tag when no author is given" do
      event = Event.build_long_form(@test_pubkey, "Content", title: "Article", kind: 30023)

      refute Enum.any?(event.tags, fn [tag | _] -> tag == "p" end)
    end

    test "adds the Pareto client tag on kind 30023 when requested" do
      event =
        Event.build_long_form(@test_pubkey, "Content", title: "Article", client: true)

      assert Event.pareto_client_tag() in event.tags
    end

    test "does not add the client tag on drafts" do
      event =
        Event.build_long_form(@test_pubkey, "Content",
          title: "Draft",
          kind: 30024,
          client: true
        )

      refute Event.pareto_client_tag() in event.tags
    end

    test "omits the client tag unless requested" do
      event = Event.build_long_form(@test_pubkey, "Content", title: "Article")

      refute Event.pareto_client_tag() in event.tags
    end

    test "builds event with title tag" do
      event = Event.build_long_form(@test_pubkey, "Content", title: "My Title")

      title_tag = Enum.find(event.tags, fn [tag | _] -> tag == "title" end)
      assert title_tag == ["title", "My Title"]
    end

    test "builds event with summary tag" do
      event = Event.build_long_form(@test_pubkey, "Content", title: "Test", summary: "A summary")

      summary_tag = Enum.find(event.tags, fn [tag | _] -> tag == "summary" end)
      assert summary_tag == ["summary", "A summary"]
    end

    test "builds event with image tag" do
      event =
        Event.build_long_form(@test_pubkey, "Content",
          title: "Test",
          image: "https://example.com/img.jpg"
        )

      image_tag = Enum.find(event.tags, fn [tag | _] -> tag == "image" end)
      assert image_tag == ["image", "https://example.com/img.jpg"]
    end

    test "adds NIP-92 imeta tags" do
      event =
        Event.build_long_form(@test_pubkey, "![Hero](https://cdn.example/hero.png)",
          title: "Test",
          image: "https://cdn.example/hero.png",
          imeta: [
            ["imeta", "url https://cdn.example/hero.png", "m image/png", "x aa", "dim 1x1"]
          ]
        )

      assert ["imeta", "url https://cdn.example/hero.png", "m image/png", "x aa", "dim 1x1"] in
               event.tags
    end

    test "builds event with identifier (d tag)" do
      event =
        Event.build_long_form(@test_pubkey, "Content",
          title: "Test",
          identifier: "my-article-slug"
        )

      d_tag = Enum.find(event.tags, fn [tag | _] -> tag == "d" end)
      assert d_tag == ["d", "my-article-slug"]
    end

    test "builds event with published_at timestamp" do
      # 2024-01-01 00:00:00 UTC
      timestamp = 1_704_067_200

      event =
        Event.build_long_form(@test_pubkey, "Content", title: "Test", published_at: timestamp)

      published_tag = Enum.find(event.tags, fn [tag | _] -> tag == "published_at" end)
      assert published_tag == ["published_at", "1704067200"]
    end

    test "builds event with hashtags" do
      event =
        Event.build_long_form(@test_pubkey, "Content",
          title: "Test",
          hashtags: ["nostr", "bitcoin"]
        )

      t_tags = Enum.filter(event.tags, fn [tag | _] -> tag == "t" end)
      assert length(t_tags) == 2
      assert ["t", "nostr"] in t_tags
      assert ["t", "bitcoin"] in t_tags
    end

    test "normalizes hashtags without turning spaces into hyphens" do
      event =
        Event.build_long_form(@test_pubkey, "Content",
          title: "Test",
          hashtags: ["#Bitcoin News", "  Nostr  "]
        )

      t_tags = Enum.filter(event.tags, fn [tag | _] -> tag == "t" end)
      assert ["t", "bitcoin news"] in t_tags
      assert ["t", "nostr"] in t_tags
    end

    test "drops duplicate hashtags after normalization" do
      assert Event.normalize_hashtags("#Bitcoin, bitcoin, BITCOIN, ") == ["bitcoin"]
    end

    test "adds NIP-32 language labels" do
      event = Event.build_long_form(@test_pubkey, "Content", title: "Test", language: "de")

      assert ["L", "ISO-639-1"] in event.tags
      assert ["l", "de", "ISO-639-1"] in event.tags
    end

    test "adds an r tag for the original article URL" do
      event =
        Event.build_long_form(@test_pubkey, "Content",
          title: "Test",
          canonical_url: "https://example.com/article"
        )

      assert ["r", "https://example.com/article"] in event.tags
    end
  end

  describe "compute_id/1" do
    test "computes deterministic event id" do
      event = %{
        pubkey: @test_pubkey,
        created_at: 1_704_067_200,
        kind: 1,
        tags: [],
        content: "Hello, Nostr!"
      }

      id1 = Event.compute_id(event)
      id2 = Event.compute_id(event)

      assert id1 == id2
      assert String.length(id1) == 64
      assert Regex.match?(~r/^[a-f0-9]+$/, id1)
    end

    test "different events produce different ids" do
      event1 = %{pubkey: @test_pubkey, created_at: 1, kind: 1, tags: [], content: "a"}
      event2 = %{pubkey: @test_pubkey, created_at: 1, kind: 1, tags: [], content: "b"}

      assert Event.compute_id(event1) != Event.compute_id(event2)
    end
  end

  describe "serialize_for_id/1" do
    test "serializes event in correct format" do
      event = %{
        pubkey: @test_pubkey,
        created_at: 1_704_067_200,
        kind: 1,
        tags: [["t", "test"]],
        content: "Hello"
      }

      json = Event.serialize_for_id(event)
      decoded = Jason.decode!(json)

      assert is_list(decoded)
      assert length(decoded) == 6
      assert Enum.at(decoded, 0) == 0
      assert Enum.at(decoded, 1) == @test_pubkey
      assert Enum.at(decoded, 2) == 1_704_067_200
      assert Enum.at(decoded, 3) == 1
      assert Enum.at(decoded, 4) == [["t", "test"]]
      assert Enum.at(decoded, 5) == "Hello"
    end
  end

  describe "build_long_form/3 additional options" do
    test "builds event with all provided options" do
      event =
        Event.build_long_form(@test_pubkey, "Content",
          title: "Test",
          summary: "Test summary"
        )

      # Should have title and summary tags
      title_tag = Enum.find(event.tags, fn [tag | _] -> tag == "title" end)
      summary_tag = Enum.find(event.tags, fn [tag | _] -> tag == "summary" end)
      assert title_tag != nil
      assert summary_tag != nil
    end

    test "builds event without optional fields" do
      event = Event.build_long_form(@test_pubkey, "Content", title: "Only Title")

      # Should have title and d tags at minimum
      title_tag = Enum.find(event.tags, fn [tag | _] -> tag == "title" end)
      assert title_tag != nil

      d_tag = Enum.find(event.tags, fn [tag | _] -> tag == "d" end)
      assert d_tag != nil
    end

    test "generates d tag from title if not provided" do
      event = Event.build_long_form(@test_pubkey, "Content", title: "My Test Title")

      d_tag = Enum.find(event.tags, fn [tag | _] -> tag == "d" end)
      assert d_tag != nil
      [_, identifier] = d_tag
      # Should be slugified or based on title
      assert is_binary(identifier)
    end

    test "uses created_at as integer timestamp" do
      event = Event.build_long_form(@test_pubkey, "Content", title: "Test")

      assert is_integer(event.created_at)
      # Should be a reasonable Unix timestamp (after year 2020)
      assert event.created_at > 1_577_836_800
    end
  end

  describe "build_long_form/3 with all options" do
    test "builds complete event with all optional fields" do
      event =
        Event.build_long_form(@test_pubkey, "# Full Content\n\nWith body.",
          title: "Complete Article",
          summary: "This is the summary",
          image: "https://example.com/image.jpg",
          identifier: "complete-article",
          published_at: 1_704_067_200,
          hashtags: ["test", "elixir"],
          client: true
        )

      # Verify all tags
      assert Enum.find(event.tags, fn [t | _] -> t == "title" end) != nil
      assert Enum.find(event.tags, fn [t | _] -> t == "summary" end) != nil
      assert Enum.find(event.tags, fn [t | _] -> t == "image" end) != nil
      assert Enum.find(event.tags, fn [t | _] -> t == "d" end) != nil
      assert Enum.find(event.tags, fn [t | _] -> t == "published_at" end) != nil

      # Check hashtags
      t_tags = Enum.filter(event.tags, fn [t | _] -> t == "t" end)
      assert length(t_tags) == 2
      assert Event.pareto_client_tag() in event.tags
    end
  end

  describe "wrap_draft/3" do
    @private_key <<1::256>>
    @author "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"

    test "encrypts an unsigned article as a NIP-37 kind 31234 wrap" do
      inner =
        Event.build_long_form(@test_pubkey, "# Draft\n\nBody",
          title: "Draft Title",
          identifier: "draft-title",
          author_pubkey: @author
        )

      assert {:ok, wrap} =
               Event.wrap_draft(inner, @private_key,
                 identifier: "draft-title",
                 author_pubkey: @author,
                 expiration: 1_800_000_000
               )

      signer_pubkey =
        @private_key |> Rss2Nostr.Nostr.Keys.derive_public_key() |> Rss2Nostr.Nostr.Keys.to_hex()

      assert wrap.kind == 31234
      assert wrap.pubkey == signer_pubkey
      refute wrap.content == inner.content
      assert ["d", "draft-title"] in wrap.tags
      assert ["k", "30023"] in wrap.tags
      assert ["expiration", "1800000000"] in wrap.tags
      assert ["p", @author] in wrap.tags

      assert {:ok, decrypted} = Event.unwrap_draft(wrap, @private_key)
      assert decrypted["kind"] == 30023
      assert decrypted["content"] == "# Draft\n\nBody"
      assert decrypted["pubkey"] == @test_pubkey
      assert ["title", "Draft Title"] in decrypted["tags"]
    end

    test "estimate_wrap_message_size/2 tracks a real signed wrap" do
      inner =
        Event.build_long_form(@test_pubkey, "# Draft\n\nBody",
          title: "Draft Title",
          identifier: "draft-title",
          author_pubkey: @author
        )

      {:ok, wrap} =
        Event.wrap_draft(inner, @private_key,
          identifier: "draft-title",
          author_pubkey: @author,
          expiration: 1_000_000_000
        )

      {:ok, signed} = Event.sign_event(wrap, @private_key)
      {:ok, message} = Jason.encode(["EVENT", signed])
      estimate = Event.estimate_wrap_message_size(inner, author_pubkey: @author)

      assert estimate == byte_size(message)
    end

    test "nip44_padded_len/1 follows the NIP-44 buckets" do
      assert Event.nip44_padded_len(32) == 32
      assert Event.nip44_padded_len(33) == 64
      assert Event.nip44_padded_len(65_535) == 65_536
    end

    test "draft_plaintext_size/1 matches the wrapped JSON payload" do
      inner =
        Event.build_long_form(@test_pubkey, "# Draft\n\nBody",
          title: "Draft Title",
          identifier: "draft-title"
        )

      {:ok, plaintext} = Event.draft_plaintext(inner)

      assert Event.draft_plaintext_size(inner) == byte_size(plaintext)
      assert Event.draft_plaintext_size(inner) < Event.max_draft_plaintext_size()
    end
  end
end
