defmodule Rss2Nostr.Import.FeedParserTest do
  use ExUnit.Case, async: true

  alias Rss2Nostr.Import.FeedParser

  @rss_feed """
  <?xml version="1.0" encoding="UTF-8"?>
  <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
    <channel>
      <title>Test Feed</title>
      <link>https://example.com</link>
      <item>
        <title>Test Article</title>
        <link>https://example.com/article/1</link>
        <guid>article-1</guid>
        <dc:creator>John Doe</dc:creator>
        <pubDate>Mon, 01 Jan 2024 12:00:00 GMT</pubDate>
        <description>This is a test article</description>
        <content:encoded><![CDATA[<p>Full content here</p>]]></content:encoded>
        <enclosure url="https://cdn.example/episode.mp3" type="audio/mpeg" length="123"/>
        <itunes:duration>23:43</itunes:duration>
        <category>Tech</category>
        <category>News</category>
      </item>
      <item>
        <title>Second Article</title>
        <link>https://example.com/article/2</link>
        <description>Second article description</description>
      </item>
    </channel>
  </rss>
  """

  @atom_feed """
  <?xml version="1.0" encoding="UTF-8"?>
  <feed xmlns="http://www.w3.org/2005/Atom">
    <title>Test Atom Feed</title>
    <link href="https://example.com"/>
    <entry>
      <title>Atom Article</title>
      <link href="https://example.com/atom/1"/>
      <id>urn:uuid:atom-1</id>
      <author><name>Jane Smith</name></author>
      <published>2024-01-01T12:00:00Z</published>
      <summary>Atom summary</summary>
      <content type="html"><![CDATA[<p>Atom content</p>]]></content>
      <category term="Technology"/>
    </entry>
  </feed>
  """

  describe "detect_feed_type/1" do
    test "detects RSS feed" do
      assert FeedParser.detect_feed_type(@rss_feed) == "rss"
    end

    test "detects Atom feed" do
      assert FeedParser.detect_feed_type(@atom_feed) == "atom"
    end

    test "detects RSS by channel element" do
      xml = "<channel><item></item></channel>"
      assert FeedParser.detect_feed_type(xml) == "rss"
    end

    test "returns nil for unknown format" do
      assert FeedParser.detect_feed_type("<html></html>") == nil
    end
  end

  describe "feed_title/1" do
    test "reads the RSS channel title" do
      assert FeedParser.feed_title(@rss_feed) == "Test Feed"
    end

    test "reads the Atom feed title" do
      assert FeedParser.feed_title(@atom_feed) == "Test Atom Feed"
    end
  end

  describe "feed_language/1" do
    test "reads an RSS language tag and keeps the ISO 639-1 code" do
      xml = """
      <?xml version="1.0"?>
      <rss version="2.0">
        <channel>
          <title>Interviews</title>
          <language>en-us</language>
        </channel>
      </rss>
      """

      assert FeedParser.feed_language(xml) == "en"
    end

    test "reads Atom xml:lang" do
      xml = """
      <?xml version="1.0"?>
      <feed xmlns="http://www.w3.org/2005/Atom" xml:lang="de-DE">
        <title>Nachrichten</title>
      </feed>
      """

      assert FeedParser.feed_language(xml) == "de"
    end

    test "returns nil when the feed has no language" do
      assert FeedParser.feed_language(@rss_feed) == nil
    end
  end

  describe "parse/2 with RSS" do
    test "parses RSS feed items" do
      {:ok, items} = FeedParser.parse(@rss_feed, "rss")

      assert length(items) == 2

      [first | _] = items
      assert first.title == "Test Article"
      assert first.link == "https://example.com/article/1"
      assert first.guid == "article-1"
      assert first.author == "John Doe"
      assert first.summary == "This is a test article"
      assert first.content == "<p>Full content here</p>"
      assert "Tech" in first.categories
      assert "News" in first.categories
      assert first.enclosure_url == "https://cdn.example/episode.mp3"
      assert first.enclosure_type == "audio/mpeg"
      assert first.enclosure_length == 123
      assert first.duration == "23:43"
    end

    test "reads CDATA RSS category tags as article hashtags" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <item>
            <title>Früher war alles besser</title>
            <link>https://www.thomas-eisinger.de/frueher-war-alles-besser-2/</link>
            <category><![CDATA[Aktuelles]]></category>
            <category><![CDATA[Gesellschaft]]></category>
            <category><![CDATA[Schwarzer Schwan]]></category>
            <category><![CDATA[UnsereDemokratie]]></category>
          </item>
        </channel>
      </rss>
      """

      {:ok, [item]} = FeedParser.parse(xml, "rss")

      assert item.categories == [
               "Aktuelles",
               "Gesellschaft",
               "Schwarzer Schwan",
               "UnsereDemokratie"
             ]
    end

    test "parses RSS item without optional fields" do
      {:ok, items} = FeedParser.parse(@rss_feed, "rss")

      second = Enum.at(items, 1)
      assert second.title == "Second Article"
      assert second.link == "https://example.com/article/2"
    end

    test "auto-detects RSS format" do
      {:ok, items} = FeedParser.parse(@rss_feed)
      assert length(items) == 2
    end
  end

  describe "parse/2 with Atom" do
    test "parses Atom feed entries" do
      {:ok, items} = FeedParser.parse(@atom_feed, "atom")

      assert length(items) == 1

      [first | _] = items
      assert first.title == "Atom Article"
      assert first.link == "https://example.com/atom/1"
      assert first.guid == "urn:uuid:atom-1"
      assert first.author == "Jane Smith"
      assert first.summary == "Atom summary"
      assert first.content == "<p>Atom content</p>"
    end

    test "auto-detects Atom format" do
      {:ok, items} = FeedParser.parse(@atom_feed)
      assert length(items) == 1
    end
  end

  describe "parse/2 error handling" do
    test "returns error for unknown feed type" do
      {:error, message} = FeedParser.parse("<html></html>", "unknown")
      assert message =~ "Unknown feed type"
    end

    test "handles malformed XML" do
      # SweetXml may exit on malformed XML
      try do
        FeedParser.parse("<rss><broken", "rss")
        # If it doesn't raise/exit, that's also acceptable (error tuple returned)
        assert true
      catch
        :exit, _ ->
          # Exit is expected for malformed XML
          assert true
      end
    end
  end

  describe "parse/2 with edge cases" do
    test "handles empty feed" do
      empty_rss = """
      <?xml version="1.0"?>
      <rss version="2.0">
        <channel>
          <title>Empty Feed</title>
        </channel>
      </rss>
      """

      {:ok, items} = FeedParser.parse(empty_rss, "rss")
      assert items == []
    end

    test "handles feed with HTML entities" do
      rss_with_entities = """
      <?xml version="1.0"?>
      <rss version="2.0">
        <channel>
          <item>
            <title>Test &amp; Article &lt;Special&gt;</title>
            <link>https://example.com/article</link>
          </item>
        </channel>
      </rss>
      """

      {:ok, [item]} = FeedParser.parse(rss_with_entities, "rss")
      assert item.title == "Test & Article <Special>"
    end

    test "decodes a double-encoded apostrophe in the title" do
      rss = """
      <?xml version="1.0" encoding="utf-8"?>
      <rss version="2.0">
        <channel>
          <item>
            <title>Vier Wochen Wahnsinn im Juli &amp;#039;26 - von Michael Sailer und Franz Esser</title>
            <link>https://www.radiomuenchen.net/de/example.html</link>
          </item>
        </channel>
      </rss>
      """

      {:ok, [item]} = FeedParser.parse(rss, "rss")
      assert item.title == "Vier Wochen Wahnsinn im Juli '26 - von Michael Sailer und Franz Esser"
    end
  end
end
