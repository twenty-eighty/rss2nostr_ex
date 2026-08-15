defmodule Rss2Nostr.Import.FeedDiscoveryTest do
  use ExUnit.Case, async: true

  alias Rss2Nostr.Import.FeedDiscovery

  @html """
  <!DOCTYPE html>
  <html>
    <head>
      <title>Example News</title>
      <meta property="og:site_name" content="Example">
      <link rel="alternate" type="application/rss+xml" title="RSS Feed"
            href="/rss.xml">
      <link rel="alternate" type="application/atom+xml" title="Atom Feed"
            href="https://example.com/atom.xml">
      <link rel="stylesheet" href="/app.css">
    </head>
    <body><h1>Hello</h1></body>
  </html>
  """

  describe "page_title/1" do
    test "prefers og:site_name" do
      assert FeedDiscovery.page_title(@html) == "Example"
    end

    test "falls back to title" do
      html = "<html><head><title> Only Title </title></head></html>"
      assert FeedDiscovery.page_title(html) == "Only Title"
    end
  end

  describe "feeds_from_html/2" do
    test "collects RSS and Atom alternate links" do
      feeds = FeedDiscovery.feeds_from_html(@html, "https://example.com/blog")

      assert Enum.any?(feeds, fn feed ->
               feed.url == "https://example.com/rss.xml" and feed.type == "rss" and
                 feed.title == "RSS Feed"
             end)

      assert Enum.any?(feeds, fn feed ->
               feed.url == "https://example.com/atom.xml" and feed.type == "atom"
             end)

      refute Enum.any?(feeds, &String.ends_with?(&1.url, "app.css"))
    end
  end

  describe "looks_like_feed_url?/1" do
    test "recognizes common feed paths" do
      assert FeedDiscovery.looks_like_feed_url?("https://example.com/feed.xml")
      assert FeedDiscovery.looks_like_feed_url?("https://example.com/rss")
      assert FeedDiscovery.looks_like_feed_url?("https://example.com/atom.xml")
      assert FeedDiscovery.looks_like_feed_url?("https://example.com/blog/feed")
      refute FeedDiscovery.looks_like_feed_url?("https://example.com")
      refute FeedDiscovery.looks_like_feed_url?("https://example.com/articles/hello")
    end
  end

  describe "discover_from_body/2" do
    test "treats a pasted feed URL as the feed even when items contain HTML" do
      body = """
      <?xml version="1.0"?>
      <rss version="2.0">
        <channel>
          <title>Direct Feed</title>
          <item>
            <title>Hello</title>
            <guid>https://example.com/hello</guid>
            <description><![CDATA[<!DOCTYPE html><html><body>Hi</body></html>]]></description>
          </item>
        </channel>
      </rss>
      """

      assert {:ok, result} =
               FeedDiscovery.discover_from_body("https://example.com/feed.xml", body)

      assert result.direct_feed
      assert result.page_title == "Direct Feed"
      assert [%{url: "https://example.com/feed.xml", type: "rss"}] = result.feeds
      assert Enum.any?(result.items, &(&1.title == "Hello"))
    end

    test "still finds alternate links on a website" do
      assert {:ok, result} =
               FeedDiscovery.discover_from_body("https://example.com", @html)

      refute result.direct_feed
      assert length(result.feeds) == 2
    end
  end

  describe "normalize_url/1" do
    test "adds https when the scheme is missing" do
      assert {:ok, "https://example.com/feed"} = FeedDiscovery.normalize_url("example.com/feed")
    end

    test "rejects non-http URLs" do
      assert {:error, _} = FeedDiscovery.normalize_url("javascript:alert(1)")
      assert {:error, _} = FeedDiscovery.normalize_url("ftp://example.com/feed")
    end
  end
end
