defmodule Rss2Nostr.Nostr.NIP92Test do
  use ExUnit.Case, async: true

  alias Rss2Nostr.Nostr.NIP92

  @png_descriptor %{
    url: "https://route96.pareto.space/abc.png",
    sha256: "aa",
    size: 70,
    type: "image/png",
    nip94: [
      ["url", "https://route96.pareto.space/abc.png"],
      ["x", "aa"],
      ["m", "image/png"],
      ["size", "70"],
      ["thumb", "https://route96.pareto.space/thumb/abc.webp"],
      ["dim", "1x1"],
      ["duration", "0"],
      ["bitrate", "0"]
    ]
  }

  describe "pairs_from_descriptor/2" do
    test "keeps nip94 fields and drops zero duration/bitrate" do
      pairs = NIP92.pairs_from_descriptor(@png_descriptor, alt: "Hero")

      assert "url https://route96.pareto.space/abc.png" in pairs
      assert "x aa" in pairs
      assert "m image/png" in pairs
      assert "dim 1x1" in pairs
      assert "thumb https://route96.pareto.space/thumb/abc.webp" in pairs
      assert "alt Hero" in pairs
      refute Enum.any?(pairs, &String.starts_with?(&1, "duration "))
      refute Enum.any?(pairs, &String.starts_with?(&1, "bitrate "))
      assert hd(pairs) =~ "url "
    end

    test "builds pairs from a plain BUD-02 descriptor" do
      pairs =
        NIP92.pairs_from_descriptor(%{
          url: "https://cdn.example/file.mp3",
          sha256: "bb",
          size: 12,
          type: "audio/mpeg"
        })

      assert pairs == [
               "url https://cdn.example/file.mp3",
               "x bb",
               "m audio/mpeg",
               "size 12"
             ]
    end
  end

  describe "tag/1" do
    test "requires url plus another field" do
      assert NIP92.tag(["url https://cdn.example/a.png", "m image/png"]) == [
               "imeta",
               "url https://cdn.example/a.png",
               "m image/png"
             ]

      assert NIP92.tag(["url https://cdn.example/a.png"]) == nil
    end
  end

  describe "tags_for_event/3" do
    test "emits imeta only for URLs in the content or featured image" do
      images = [
        %{
          uploaded_url: "https://cdn.example/hero.png",
          mime_type: "image/png",
          sha256: "aa",
          imeta: ["url https://cdn.example/hero.png", "m image/png", "x aa"]
        },
        %{
          uploaded_url: "https://cdn.example/unused.png",
          mime_type: "image/png",
          imeta: ["url https://cdn.example/unused.png", "m image/png"]
        },
        %{
          uploaded_url: "https://cdn.example/audio.mp3",
          mime_type: "audio/mpeg",
          imeta: ["url https://cdn.example/audio.mp3", "m audio/mpeg"]
        }
      ]

      tags =
        NIP92.tags_for_event(images, "[Audio](https://cdn.example/audio.mp3)",
          featured: "https://cdn.example/hero.png"
        )

      urls =
        Enum.map(tags, fn ["imeta" | pairs] -> NIP92.url_from_pairs(pairs) end)

      assert "https://cdn.example/hero.png" in urls
      assert "https://cdn.example/audio.mp3" in urls
      refute "https://cdn.example/unused.png" in urls
    end
  end
end
