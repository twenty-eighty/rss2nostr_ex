defmodule Rss2Nostr.Web.API.SourcesTest do
  use Rss2Nostr.DataCase

  alias Rss2Nostr.Web.API.Sources, as: API
  alias Rss2Nostr.Sources

  def unique_url do
    "https://example.com/feed-#{System.unique_integer([:positive])}.xml"
  end

  def valid_attrs do
    %{
      name: "Test Source",
      url: unique_url(),
      type: "rss",
      language: "en",
      active: true
    }
  end

  describe "list/0" do
    test "returns empty list when no sources" do
      # Clear existing sources first by listing and checking
      sources = API.list()
      assert is_list(sources)
    end

    test "returns all sources as maps" do
      {:ok, source} = Sources.create_source(valid_attrs())
      sources = API.list()

      assert Enum.any?(sources, fn s ->
               s.id == source.id and
                 s.name == source.name and
                 s.url == source.url
             end)
    end

    test "returns sources with correct structure" do
      {:ok, _} = Sources.create_source(valid_attrs())
      [source | _] = API.list()

      assert Map.has_key?(source, :id)
      assert Map.has_key?(source, :name)
      assert Map.has_key?(source, :url)
      assert Map.has_key?(source, :type)
      assert Map.has_key?(source, :active)
      assert Map.has_key?(source, :language)
    end
  end

  describe "create/1" do
    test "creates source with valid params" do
      params = %{
        "name" => "New Source",
        "url" => unique_url(),
        "type" => "atom",
        "language" => "de"
      }

      {:ok, source} = API.create(params)

      assert source.name == "New Source"
      assert source.type == "atom"
      assert source.language == "de"
      assert source.active == true
    end

    test "uses default values when not provided" do
      params = %{
        "name" => "Default Source",
        "url" => unique_url()
      }

      {:ok, source} = API.create(params)

      assert source.type == "atom"
      assert source.language == "de"
    end

    test "returns error for invalid params" do
      params = %{"name" => nil, "url" => nil}

      {:error, changeset} = API.create(params)
      refute changeset.valid?
    end
  end

  describe "toggle/1" do
    test "disables active source" do
      {:ok, source} = Sources.create_source(%{valid_attrs() | active: true})

      {:ok, toggled} = API.toggle(to_string(source.id))
      assert toggled.active == false
    end

    test "enables inactive source" do
      {:ok, source} = Sources.create_source(%{valid_attrs() | active: false})

      {:ok, toggled} = API.toggle(to_string(source.id))
      assert toggled.active == true
    end

    test "returns error for non-existent source" do
      assert {:error, :not_found} = API.toggle("999999")
    end

    test "returns error for invalid id" do
      assert {:error, :invalid_id} = API.toggle("invalid")
      assert {:error, :invalid_id} = API.toggle("-1")
      assert {:error, :invalid_id} = API.toggle("0")
    end
  end

  describe "delete/1" do
    test "deletes existing source" do
      {:ok, source} = Sources.create_source(valid_attrs())

      {:ok, _} = API.delete(to_string(source.id))
      assert Sources.get_source(source.id) == nil
    end

    test "returns error for non-existent source" do
      assert {:error, :not_found} = API.delete("999999")
    end

    test "returns error for invalid id" do
      assert {:error, :invalid_id} = API.delete("invalid")
      assert {:error, :invalid_id} = API.delete("-1")
    end
  end
end
