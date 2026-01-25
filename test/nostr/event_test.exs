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
          client: "rss2nostr"
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
    end
  end
end
