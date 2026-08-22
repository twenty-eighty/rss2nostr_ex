defmodule Rss2Nostr.MCP.ActionsTest do
  use Rss2Nostr.DataCase

  alias Rss2Nostr.MCP.Actions
  alias Rss2Nostr.Sources

  def unique_url do
    "https://example.com/mcp-#{System.unique_integer([:positive])}.xml"
  end

  test "get_status returns source and post counts" do
    assert {:ok, overview} = Actions.get_status()
    assert is_map(overview.sources)
    assert is_map(overview.posts)
  end

  test "add_source and list_sources" do
    url = unique_url()

    assert {:ok, source} =
             Actions.add_source(%{
               name: "MCP Source",
               url: url,
               language: "en",
               type: "rss"
             })

    assert source.name == "MCP Source"
    assert source.url == url
    assert source.language == "en"

    assert {:ok, %{sources: sources}} = Actions.list_sources()
    assert Enum.any?(sources, &(&1.id == source.id))
  end

  test "add_source requires a name and url" do
    assert {:error, message} = Actions.add_source(%{url: unique_url()})
    assert message =~ "name"
  end

  test "get_source and toggle_source" do
    {:ok, created} =
      Sources.create_source(%{
        name: "Toggle MCP",
        url: unique_url(),
        type: "rss",
        language: "en",
        active: true
      })

    assert {:ok, fetched} = Actions.get_source(%{source_id: created.id})
    assert fetched.id == created.id
    assert fetched.active == true

    assert {:ok, toggled} = Actions.toggle_source(%{source_id: created.id})
    assert toggled.active == false
  end

  test "delete_source removes the source" do
    {:ok, created} =
      Sources.create_source(%{
        name: "Delete MCP",
        url: unique_url(),
        type: "rss",
        language: "en"
      })

    assert {:ok, %{deleted: true, id: id}} = Actions.delete_source(%{source_id: created.id})
    assert id == created.id
    assert {:error, "Source not found"} = Actions.get_source(%{source_id: created.id})
  end

  test "list_posts returns a page" do
    assert {:ok, %{posts: posts, page: 1}} = Actions.list_posts(%{})
    assert is_list(posts)
  end

  test "unknown post is an error" do
    assert {:error, "Post not found"} = Actions.get_post(%{post_id: 9_999_999})
  end

  test "update_source stores staging hold and notify pubkey" do
    hex = "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
    {:ok, npub} = Rss2Nostr.Nostr.NIP19.encode_npub(hex)

    {:ok, created} =
      Sources.create_source(%{
        name: "Staging MCP",
        url: unique_url(),
        type: "rss",
        language: "en"
      })

    assert {:ok, updated} =
             Actions.update_source(%{
               source_id: created.id,
               staging_hold_minutes: 120,
               notify_pubkey: npub,
               fixed_hashtags: "#PatrikBaab, bitcoin, patrikbaab",
               excluded_hashtags: "ROOT, Haupteintrag, root"
             })

    assert updated.staging_hold_minutes == 120
    assert updated.notify_pubkey == hex
    assert updated.fixed_hashtags == ["patrikbaab", "bitcoin"]
    assert updated.excluded_hashtags == ["root", "haupteintrag"]
  end
end
