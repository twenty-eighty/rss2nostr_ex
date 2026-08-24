defmodule Rss2Nostr.Web.Views.SourcesTest do
  use Rss2NostrWeb.ConnCase, async: false

  alias Rss2Nostr.Sources, as: SourcesContext

  def unique_url do
    "https://example.com/feed-#{System.unique_integer([:positive])}.xml"
  end

  describe "index" do
    test "returns HTML with sources list", %{conn: conn} do
      html = page(conn, "/sources")

      assert is_binary(html)
      assert html =~ "<html"
      assert html =~ "Sources"
    end

    test "shows add source button", %{conn: conn} do
      html = page(conn, "/sources")

      assert html =~ "Add" or html =~ "New" or html =~ "/sources/new"
    end

    test "lists existing sources", %{conn: conn} do
      {:ok, source} =
        SourcesContext.create_source(%{
          name: "Test View Source",
          url: unique_url(),
          type: "rss",
          language: "en",
          active: true
        })

      html = page(conn, "/sources")

      assert html =~ source.name
      assert html =~ "source-avatar"
      assert html =~ "/sources/#{source.id}"
      assert html =~ "Open"
      assert html =~ "Duplicate"
    end

    test "includes the author pubkey for the profile image", %{conn: conn} do
      pubkey = "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"

      {:ok, source} =
        SourcesContext.create_source(%{
          name: "Avatar Source",
          url: unique_url(),
          type: "rss",
          language: "en",
          pubkey: pubkey
        })

      html = page(conn, "/sources")

      assert html =~ source.name
      assert html =~ ~s(data-pubkey="#{pubkey}")
      assert html =~ ~s(phx-hook="SourceAvatars")
    end
  end

  describe "compose" do
    test "renders composition controls for an existing source", %{conn: conn} do
      {:ok, source} =
        SourcesContext.create_source(%{
          name: "Compose View Source",
          url: unique_url(),
          type: "rss",
          language: "en",
          fetch_source_from: "content",
          options: %{"body_selector" => "div.entry-content"}
        })

      html = page(conn, "/sources/#{source.id}")

      assert html =~ source.name
      assert html =~ "div.entry-content"
      assert html =~ "Which block is the article?"
      assert html =~ "body-regions-details"
      assert html =~ "<summary>Which block is the article?</summary>"
      refute html =~ ~r/id="body-regions-details"[^>]*\bopen\b/
      assert html =~ "body-regions"
      assert html =~ "Start here"
      assert html =~ "<summary>Start here</summary>"
      assert html =~ "start-blocks"
      assert html =~ "Technical settings"
      assert html =~ "Nostr event preview"
      assert html =~ "excluded_hashtags"
      assert html =~ "Excluded hashtags"
      assert html =~ "data-original-article"
      assert html =~ "Open original article"
      assert html =~ "compose-preview-hero"
      assert html =~ "compose-preview-rendered"
      assert html =~ "compose-preview-event"
      assert html =~ "show-split-parts"
      assert html =~ "Show split parts"
      assert html =~ ~s(data-preview-tab="event")
      refute html =~ "Link rows"
      refute html =~ "conversion_rules"
      assert html =~ "container-wide"
      assert html =~ "Markdown"
      assert html =~ "source-tabs"
      assert html =~ "Articles"
      assert html =~ "Publishing"

      feed = page(conn, "/sources/#{source.id}?tab=feed")
      assert feed =~ "Feed URL"
      assert feed =~ "Duplicate"
      assert feed =~ ~s(name="url")
      assert feed =~ ~s(id="language")
      assert feed =~ ~s(name="language")
      assert feed =~ ~s(value="en")
      assert feed =~ "English (en)"

      publishing = page(conn, "/sources/#{source.id}?tab=publishing")
      assert publishing =~ "Setup"
      refute publishing =~ "Back to setup"
      assert publishing =~ "Draft (encrypted, NIP-37)"
      assert publishing =~ "Draft (unencrypted)"
      assert publishing =~ "Article (kind 30023)"
      assert publishing =~ "Video (kind 34235)"
      assert publishing =~ "Mirror to Blossom"
      assert publishing =~ "Link original URL"
      assert publishing =~ "Bunker URL"
      assert publishing =~ "staging_hold_minutes"
      assert publishing =~ "notify_pubkey"
      assert publishing =~ "fixed_hashtags"
      assert publishing =~ "Fixed hashtags"
      assert publishing =~ "excluded_hashtags"
      assert publishing =~ "Excluded hashtags"
      assert publishing =~ "Hold before auto-publish"

      articles = page(conn, "/sources/#{source.id}?tab=articles")
      assert articles =~ "Publish selected"
      assert articles =~ "Import now"
      assert articles =~ "Reprocess selected"
      assert articles =~ "select-all-articles"
      assert articles =~ "article-toolbar"
    end

    test "preview links return to the articles tab", %{conn: conn} do
      {:ok, source} =
        SourcesContext.create_source(%{
          name: "Articles Preview Source",
          url: unique_url(),
          type: "rss",
          language: "en"
        })

      url = "https://example.com/article-#{System.unique_integer([:positive])}"

      {:ok, post} =
        Rss2Nostr.Posts.create_post(%{
          title: "Preview Return Article",
          source_url: url,
          source_url_hash: Rss2Nostr.Posts.Post.generate_url_hash(url),
          status: 2,
          source_id: source.id
        })

      html = page(conn, "/sources/#{source.id}?tab=articles")
      expected = URI.encode_www_form("/sources/#{source.id}?tab=articles")

      assert html =~ "/posts/#{post.id}?return_to=#{expected}"
    end

    test "lets pending-image articles be selected for reprocess", %{conn: conn} do
      {:ok, source} =
        SourcesContext.create_source(%{
          name: "Pending Select Source",
          url: unique_url(),
          type: "rss",
          language: "en"
        })

      url = "https://example.com/article-#{System.unique_integer([:positive])}"

      {:ok, post} =
        Rss2Nostr.Posts.create_post(%{
          title: "Pending Pixel Article",
          source_url: url,
          source_url_hash: Rss2Nostr.Posts.Post.generate_url_hash(url),
          status: 9,
          source_id: source.id
        })

      html = page(conn, "/sources/#{source.id}?tab=articles")

      assert html =~ ~s(name="post_ids[]" value="#{post.id}")
      assert html =~ ~s(data-publishable="false")
      assert html =~ "js-upload-images"
      assert html =~ "Reprocess selected"
    end

    test "makes the mode badge switch an automated source back to setup", %{conn: conn} do
      {:ok, source} =
        SourcesContext.create_source(%{
          name: "Automated Badge Source",
          url: unique_url(),
          type: "rss",
          language: "en",
          publish_as: "article",
          signing_nsec: "0000000000000000000000000000000000000000000000000000000000000001",
          mode: "automated"
        })

      html = page(conn, "/sources/#{source.id}?tab=articles")

      assert html =~ "Automated"
      assert html =~ ~s(phx-click="set_mode")
      assert html =~ ~s(phx-value-mode="setup")
      refute html =~ "Back to setup"
    end

    test "pre-fills the Corbett article block from the feed URL", %{conn: conn} do
      {:ok, source} =
        SourcesContext.create_source(%{
          name: "Corbett Compose Source",
          url:
            "https://www.corbettreport.com/newinterviewrss-#{System.unique_integer([:positive])}.xml",
          type: "rss",
          language: "en"
        })

      html = page(conn, "/sources/#{source.id}")

      assert html =~ ~s(name="body_selector")
      assert html =~ "div.et_pb_column_0_tb_body"
      refute html =~ ~r/id="body-regions-details"[^>]*\bopen\b/
    end

    test "opens the body-region picker when no known schema is applied", %{conn: conn} do
      {:ok, source} =
        SourcesContext.create_source(%{
          name: "Unknown Schema Source",
          url: unique_url(),
          type: "rss",
          language: "en",
          options: %{"body_selector" => "div.custom-body"}
        })

      html = page(conn, "/sources/#{source.id}")

      assert html =~ ~r/id="body-regions-details"[^>]*\bopen\b/
    end

    test "keeps an unknown stored language in the select", %{conn: conn} do
      {:ok, source} =
        SourcesContext.create_source(%{
          name: "Custom Language Source",
          url: unique_url(),
          type: "rss",
          language: "eo"
        })

      feed = page(conn, "/sources/#{source.id}?tab=feed")
      assert feed =~ ~s(value="eo")
      assert feed =~ "eo"
      refute feed =~ "Intended for public relays"
    end
  end

  describe "new" do
    test "returns form HTML", %{conn: conn} do
      html = page(conn, "/sources/new")

      assert is_binary(html)
      assert html =~ "<form"
      assert html =~ "Website or feed URL"
      assert html =~ "Find feeds"
      assert html =~ ~s(id="submit-source")
      assert html =~ "disabled"
      assert html =~ "Publish as"
      assert html =~ "Draft (encrypted, NIP-37)"
      assert html =~ "Draft (unencrypted)"
      assert html =~ "Article (kind 30023)"
      assert html =~ "Video (kind 34235)"
      assert html =~ "Drafts are sent to the draft relay list"
      refute html =~ "Intended for public relays"
      assert html =~ "Author public key"
      assert html =~ "signing_nsec"
      assert html =~ "bunker_connection"
      assert html =~ ~s(id="language")
      assert html =~ ~s(name="language")
      assert html =~ ~s(value="de")
      assert html =~ "German (de)"
      assert html =~ ~s(value="en")
      assert html =~ "English (en)"
      refute html =~ "compose-preview-rendered"
    end

    test "includes submit button", %{conn: conn} do
      html = page(conn, "/sources/new")

      assert html =~ "submit" or html =~ "Save" or html =~ "Create" or html =~ "Add"
    end
  end
end
