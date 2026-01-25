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
    end
  end

  describe "new/1" do
    test "returns form HTML" do
      html = Sources.new()

      assert is_binary(html)
      assert html =~ "<form"
      assert html =~ "name" or html =~ "Name"
      assert html =~ "url" or html =~ "URL"
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
