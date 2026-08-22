defmodule Rss2Nostr.Processing.YoutubeTest do
  use ExUnit.Case, async: true

  alias Rss2Nostr.Processing.Youtube

  describe "video_id/1" do
    test "parses watch, embed, shorts, and youtu.be URLs" do
      id = "bLA0a0xiy_g"

      assert Youtube.video_id("https://www.youtube.com/watch?v=#{id}") == id
      assert Youtube.video_id("https://www.youtube.com/embed/#{id}") == id
      assert Youtube.video_id("https://www.youtube.com/shorts/#{id}") == id
      assert Youtube.video_id("https://youtu.be/#{id}") == id
    end
  end

  describe "enrich_markdown/2" do
    test "replaces generic Watch on YouTube text with the video title" do
      markdown = "[Watch on YouTube](https://www.youtube.com/watch?v=bLA0a0xiy_g)"

      enriched =
        Youtube.enrich_markdown(markdown,
          enabled: true,
          fetch: fn "bLA0a0xiy_g" -> "The Real Video Title" end
        )

      assert enriched == "[The Real Video Title](https://www.youtube.com/watch?v=bLA0a0xiy_g)"
    end

    test "leaves a YOUTUBE platform label unchanged" do
      markdown = "[YOUTUBE](https://www.youtube.com/watch?v=bLA0a0xiy_g)"

      enriched =
        Youtube.enrich_markdown(markdown,
          enabled: true,
          fetch: fn _ -> "Should not be used" end
        )

      assert enriched == markdown
    end

    test "leaves a specific title unchanged" do
      markdown = "[My interview](https://www.youtube.com/watch?v=bLA0a0xiy_g)"

      enriched =
        Youtube.enrich_markdown(markdown,
          enabled: true,
          fetch: fn _ -> "Should not be used" end
        )

      assert enriched == markdown
    end

    test "keeps the generic label when the title cannot be fetched" do
      markdown = "[Watch on YouTube](https://www.youtube.com/watch?v=bLA0a0xiy_g)"

      assert Youtube.enrich_markdown(markdown, enabled: true, fetch: fn _ -> nil end) == markdown
    end

    test "replaces a translated generic YouTube label with the video title" do
      markdown = "[Auf YouTube ansehen](https://www.youtube.com/watch?v=bLA0a0xiy_g)"

      enriched =
        Youtube.enrich_markdown(markdown,
          enabled: true,
          fetch: fn "bLA0a0xiy_g" -> "The Real Video Title" end
        )

      assert enriched == "[The Real Video Title](https://www.youtube.com/watch?v=bLA0a0xiy_g)"
    end
  end
end
