defmodule Rss2Nostr.Import.ImporterTest do
  use Rss2Nostr.DataCase

  alias Rss2Nostr.Import.Importer
  alias Rss2Nostr.Sources

  def unique_url do
    "https://example.com/feed-#{System.unique_integer([:positive])}.xml"
  end

  describe "import_all/1" do
    test "returns empty list when no active sources" do
      result = Importer.import_all()

      assert is_list(result)
    end

    test "processes active sources" do
      {:ok, _source} =
        Sources.create_source(%{
          name: "Import Test Source",
          url: unique_url(),
          type: "rss",
          language: "en",
          active: true
        })

      result = Importer.import_all()

      assert is_list(result)
      # Each result should have the expected structure
      Enum.each(result, fn r ->
        assert Map.has_key?(r, :source)
        assert Map.has_key?(r, :imported)
        assert Map.has_key?(r, :skipped)
        assert Map.has_key?(r, :errors)
      end)
    end
  end

  describe "import_from_source/2" do
    test "returns result structure with source" do
      {:ok, source} =
        Sources.create_source(%{
          name: "Direct Import Test",
          url: unique_url(),
          type: "rss",
          language: "en",
          active: true
        })

      result = Importer.import_from_source(source)

      assert result.source.id == source.id
      assert is_integer(result.imported)
      assert is_integer(result.skipped)
      assert is_list(result.errors)
    end

    test "handles fetch errors gracefully" do
      {:ok, source} =
        Sources.create_source(%{
          name: "Bad URL Source",
          url: "https://nonexistent.invalid/feed.xml",
          type: "rss",
          language: "en",
          active: true
        })

      result = Importer.import_from_source(source)

      assert result.source.id == source.id
      assert result.errors != []
    end
  end

  describe "import_from_source_id/2" do
    test "imports from source by id" do
      {:ok, source} =
        Sources.create_source(%{
          name: "ID Import Test",
          url: unique_url(),
          type: "rss",
          language: "en",
          active: true
        })

      {:ok, result} = Importer.import_from_source_id(source.id)

      assert result.source.id == source.id
    end

    test "returns error for non-existent source" do
      assert {:error, :source_not_found} = Importer.import_from_source_id(999_999)
    end
  end
end
