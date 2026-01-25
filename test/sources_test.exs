defmodule Rss2Nostr.SourcesTest do
  use Rss2Nostr.DataCase

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

  describe "list_sources/0" do
    test "returns all sources" do
      {:ok, source} = Sources.create_source(valid_attrs())
      sources = Sources.list_sources()

      assert sources != []
      assert Enum.any?(sources, fn s -> s.id == source.id end)
    end
  end

  describe "list_active_sources/0" do
    test "returns only active sources" do
      {:ok, active} = Sources.create_source(%{valid_attrs() | active: true})
      {:ok, inactive} = Sources.create_source(%{valid_attrs() | name: "Inactive", active: false})

      sources = Sources.list_active_sources()

      assert Enum.any?(sources, fn s -> s.id == active.id end)
      refute Enum.any?(sources, fn s -> s.id == inactive.id end)
    end
  end

  describe "get_source/1" do
    test "returns the source with given id" do
      {:ok, source} = Sources.create_source(valid_attrs())
      found = Sources.get_source(source.id)

      assert found.id == source.id
      assert found.name == source.name
    end

    test "returns nil for non-existent id" do
      assert Sources.get_source(-1) == nil
    end
  end

  describe "get_source!/1" do
    test "returns the source with given id" do
      {:ok, source} = Sources.create_source(valid_attrs())
      found = Sources.get_source!(source.id)

      assert found.id == source.id
    end

    test "raises for non-existent id" do
      assert_raise Ecto.NoResultsError, fn ->
        Sources.get_source!(-1)
      end
    end
  end

  describe "create_source/1" do
    test "creates source with valid attrs" do
      attrs = valid_attrs()
      {:ok, source} = Sources.create_source(attrs)

      assert source.name == "Test Source"
      assert source.url == attrs.url
      assert source.type == "rss"
      assert source.active == true
    end

    test "returns error changeset with invalid attrs" do
      {:error, changeset} = Sources.create_source(%{name: nil, url: nil})

      refute changeset.valid?
    end
  end

  describe "update_source/2" do
    test "updates source with valid attrs" do
      {:ok, source} = Sources.create_source(valid_attrs())
      {:ok, updated} = Sources.update_source(source, %{name: "Updated Name"})

      assert updated.name == "Updated Name"
      assert updated.id == source.id
    end
  end

  describe "delete_source/1" do
    test "deletes the source" do
      {:ok, source} = Sources.create_source(valid_attrs())
      {:ok, _deleted} = Sources.delete_source(source)

      assert Sources.get_source(source.id) == nil
    end
  end

  describe "enable_source/1" do
    test "enables an inactive source" do
      {:ok, source} = Sources.create_source(%{valid_attrs() | active: false})
      {:ok, enabled} = Sources.enable_source(source)

      assert enabled.active == true
    end

    test "enables source by id" do
      {:ok, source} = Sources.create_source(%{valid_attrs() | active: false})
      {:ok, enabled} = Sources.enable_source(source.id)

      assert enabled.active == true
    end
  end

  describe "disable_source/1" do
    test "disables an active source" do
      {:ok, source} = Sources.create_source(%{valid_attrs() | active: true})
      {:ok, disabled} = Sources.disable_source(source)

      assert disabled.active == false
    end

    test "disables source by id" do
      {:ok, source} = Sources.create_source(%{valid_attrs() | active: true})
      {:ok, disabled} = Sources.disable_source(source.id)

      assert disabled.active == false
    end
  end

  describe "count_sources/0" do
    test "returns total count of sources" do
      initial_count = Sources.count_sources()

      {:ok, _} = Sources.create_source(valid_attrs())
      {:ok, _} = Sources.create_source(%{valid_attrs() | name: "Second"})

      assert Sources.count_sources() == initial_count + 2
    end
  end

  describe "count_active_sources/0" do
    test "returns count of active sources" do
      initial_count = Sources.count_active_sources()

      {:ok, _} = Sources.create_source(%{valid_attrs() | active: true})
      {:ok, _} = Sources.create_source(%{valid_attrs() | name: "Inactive", active: false})

      assert Sources.count_active_sources() == initial_count + 1
    end
  end
end
