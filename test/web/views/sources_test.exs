defmodule Rss2Nostr.Web.Views.SourcesTest do
  use Rss2Nostr.DataCase

  alias Rss2Nostr.Web.Views.Sources
  alias Rss2Nostr.Sources, as: SourcesContext

  def unique_url do
    "https://example.com/feed-#{System.unique_integer([:positive])}.xml"
  end

  describe "index/0" do
    test "returns HTML with sources list" do
      html = Sources.index()

      assert is_binary(html)
      assert html =~ "<html"
      assert html =~ "Sources"
    end

    test "shows add source button" do
      html = Sources.index()

      assert html =~ "Add" or html =~ "New" or html =~ "/sources/new"
    end

    test "lists existing sources" do
      {:ok, source} =
        SourcesContext.create_source(%{
          name: "Test View Source",
          url: unique_url(),
          type: "rss",
          language: "en",
          active: true
        })

      html = Sources.index()

      assert html =~ source.name
      assert html =~ "source-avatar"
      assert html =~ "/sources/#{source.id}"
      assert html =~ "Open"
      assert html =~ "/sources/#{source.id}/duplicate"
      assert html =~ "Duplicate"
    end

    test "includes the author pubkey for the profile image" do
      pubkey = "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"

      {:ok, source} =
        SourcesContext.create_source(%{
          name: "Avatar Source",
          url: unique_url(),
          type: "rss",
          language: "en",
          pubkey: pubkey
        })

      html = Sources.index()

      assert html =~ source.name
      assert html =~ ~s(data-pubkey="#{pubkey}")
      assert html =~ "kinds: [0]"
    end
  end

  describe "compose/1" do
    test "renders composition controls for an existing source" do
      {:ok, source} =
        SourcesContext.create_source(%{
          name: "Compose View Source",
          url: unique_url(),
          type: "rss",
          language: "en",
          fetch_source_from: "content",
          options: %{"body_selector" => "div.entry-content"}
        })

      html = Sources.compose(source)

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
      assert html =~ "data-original-article"
      assert html =~ "Open original article"
      assert html =~ "compose-preview-hero"
      assert html =~ "compose-preview-rendered"
      assert html =~ "compose-preview-event"
      assert html =~ "show-split-parts"
      assert html =~ "Show split parts"
      assert html =~ "data-preview-tab=\"event\""
      refute html =~ "Link rows"
      refute html =~ "conversion_rules"
      assert html =~ "container-wide"
      assert html =~ "Markdown"
      assert html =~ "source-tabs"
      assert html =~ "Articles"
      assert html =~ "Publishing"

      feed = Sources.show(source, tab: "feed")
      assert feed =~ "Feed URL"
      assert feed =~ "Duplicate"
      assert feed =~ ~s(name="url")
      assert feed =~ ~s(<select id="language" name="language">)
      assert feed =~ ~s[<option value="en" selected>English (en)</option>]

      publishing = Sources.show(source, tab: "publishing")
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
      assert publishing =~ "Hold before auto-publish"

      articles = Sources.show(source, tab: "articles")
      assert articles =~ "Publish selected"
      assert articles =~ "Import now"
      assert articles =~ "Reprocess selected"
      assert articles =~ "js-articles-bulk"
      assert articles =~ ~s(js-articles-bulk" form="articles-bulk-form" disabled)
      assert articles =~ "select-all-articles"
      assert articles =~ "article-toolbar"
      assert articles =~ "js-upload-images"
    end

    test "makes the mode badge switch an automated source back to setup" do
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

      html = Sources.show(source, tab: "articles")

      assert html =~ "Automated"
      assert html =~ ~s(name="mode" value="setup")
      assert html =~ ~s(name="tab" value="articles")
      refute html =~ "Back to setup"
    end

    test "pre-fills the Corbett article block from the feed URL" do
      {:ok, source} =
        SourcesContext.create_source(%{
          name: "Corbett Compose Source",
          url: "https://www.corbettreport.com/newinterviewrss-#{System.unique_integer([:positive])}.xml",
          type: "rss",
          language: "en"
        })

      html = Sources.compose(source)

      assert html =~ ~s(name="body_selector" value="div.et_pb_column_0_tb_body")
      refute html =~ ~r/id="body-regions-details"[^>]*\bopen\b/
    end

    test "opens the body-region picker when no known schema is applied" do
      {:ok, source} =
        SourcesContext.create_source(%{
          name: "Unknown Schema Source",
          url: unique_url(),
          type: "rss",
          language: "en",
          options: %{"body_selector" => "div.custom-body"}
        })

      html = Sources.compose(source)

      assert html =~ ~r/id="body-regions-details"[^>]*\bopen\b/
    end

    test "keeps an unknown stored language in the select" do
      {:ok, source} =
        SourcesContext.create_source(%{
          name: "Custom Language Source",
          url: unique_url(),
          type: "rss",
          language: "eo"
        })

      feed = Sources.show(source, tab: "feed")
      assert feed =~ ~s(<option value="eo" selected>eo</option>)
      refute feed =~ "Intended for public relays"
    end
  end

  describe "new/1" do
    test "returns form HTML" do
      html = Sources.new()

      assert is_binary(html)
      assert html =~ "<form"
      assert html =~ "Website or feed URL"
      assert html =~ "Find feeds"
      assert html =~ "id=\"submit-source\""
      assert html =~ "disabled"
      assert html =~ "function formComplete"
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
      assert html =~ ~s(<select id="language" name="language">)
      assert html =~ ~s[<option value="de" selected>German (de)</option>]
      assert html =~ ~s[<option value="en">English (en)</option>]
      assert html =~ "function applyLanguage"
      refute html =~ "compose-preview-rendered"
    end

    test "shows error messages when provided" do
      errors = %{name: ["can't be blank"], url: ["is invalid"]}
      html = Sources.new(errors: errors)

      assert html =~ "blank" or html =~ "invalid" or html =~ "error"
    end

    test "includes submit button" do
      html = Sources.new()

      assert html =~ "submit" or html =~ "Save" or html =~ "Create" or html =~ "Add"
    end
  end
end
