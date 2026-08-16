defmodule Rss2Nostr.Import.ItemIdentityTest do
  use ExUnit.Case, async: true

  alias Rss2Nostr.Import.ItemIdentity

  describe "media_without_page?/1" do
    test "skips an mp3 guid with no page link" do
      assert ItemIdentity.media_without_page?(%{
               guid: "https://www.corbettreport.com/mp3/episode506_reading.mp3",
               link: nil
             })
    end

    test "skips a video enclosure with no page link" do
      assert ItemIdentity.media_without_page?(%{
               guid: "video-1",
               link: nil,
               enclosure_url: "https://cdn.example/nwnw639.mp4",
               enclosure_type: "video/mp4"
             })
    end

    test "keeps media when a page link is present" do
      refute ItemIdentity.media_without_page?(%{
               guid: "https://www.corbettreport.com/mp3/2026-08-06_James_Evan_Pilato.mp3",
               link: "https://corbettreport.com/nwnw639/"
             })
    end

    test "keeps a page-only article" do
      refute ItemIdentity.media_without_page?(%{
               guid: "https://corbettreport.com/james-the-fact-checker/",
               link: "https://corbettreport.com/james-the-fact-checker/"
             })
    end
  end

  describe "page_url/1" do
    test "prefers link over a media guid" do
      assert ItemIdentity.page_url(%{
               link: "https://corbettreport.com/nwnw639/",
               guid: "https://www.corbettreport.com/mp3/show.mp3"
             }) == "https://corbettreport.com/nwnw639/"
    end

    test "uses a page guid when link is missing" do
      assert ItemIdentity.page_url(%{
               link: nil,
               guid: "https://corbettreport.com/james-the-fact-checker/"
             }) == "https://corbettreport.com/james-the-fact-checker/"
    end

    test "returns nil for media-only items" do
      assert ItemIdentity.page_url(%{
               link: nil,
               guid: "https://www.corbettreport.com/mp4/nwnw639.mp4"
             }) == nil
    end
  end

  describe "lookup_keys/1" do
    test "includes www and trailing-slash variants" do
      keys = ItemIdentity.lookup_keys("https://www.corbettreport.com/nwnw639/")

      assert "https://corbettreport.com/nwnw639" in keys
      assert "https://www.corbettreport.com/nwnw639/" in keys
    end

    test "keeps a non-URL guid" do
      assert ItemIdentity.lookup_keys("article-1") == ["article-1"]
    end
  end
end
