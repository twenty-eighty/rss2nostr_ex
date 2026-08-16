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
      assert html =~ "body-regions"
      assert html =~ "Start here"
      assert html =~ "start-blocks"
      assert html =~ "Technical settings"
      assert html =~ "Nostr event preview"
      assert html =~ "data-original-article"
      assert html =~ "Open original article"
      assert html =~ "compose-preview-rendered"
      assert html =~ "compose-preview-event"
      assert html =~ "show-split-parts"
      assert html =~ "Show split parts"
      assert html =~ "data-preview-tab=\"event\""
      assert html =~ "Link rows"
      assert html =~ "conversion_rules"
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
      assert publishing =~ "Draft (encrypted, NIP-37)"
      assert publishing =~ "Draft (unencrypted)"
      assert publishing =~ "Article (kind 30023)"
      assert publishing =~ "Bunker URL"
      assert publishing =~ "staging_hold_minutes"
      assert publishing =~ "notify_pubkey"
      assert publishing =~ "fixed_hashtags"
      assert publishing =~ "Fixed hashtags"
      assert publishing =~ "Hold before auto-publish"

      articles = Sources.show(source, tab: "articles")
      assert articles =~ "Publish selected"
      assert articles =~ "Import now"
      assert articles =~ "js-upload-images"
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
      assert html =~ "Publish as"
      assert html =~ "Draft (encrypted, NIP-37)"
      assert html =~ "Draft (unencrypted)"
      assert html =~ "Article (kind 30023)"
      assert html =~ "Author public key"
      assert html =~ "signing_nsec"
      assert html =~ "bunker_connection"
      assert html =~ ~s(<select id="language" name="language">)
      assert html =~ ~s[<option value="de" selected>German (de)</option>]
      assert html =~ ~s[<option value="en">English (en)</option>]
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
