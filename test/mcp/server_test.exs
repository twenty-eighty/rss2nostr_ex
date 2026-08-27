defmodule Rss2Nostr.MCP.ServerTest do
  use ExUnit.Case, async: true

  alias Rss2Nostr.MCP.Server

  test "lists management tools" do
    {:ok, tools, nil, _state} = Server.handle_list_tools(nil, %{})
    names = Enum.map(tools, & &1.name)

    assert "add_source" in names
    assert "list_sources" in names
    assert "import_source" in names
    assert "list_posts" in names
    assert "publish_post" in names
    assert "update_post" in names
    assert "revise_post" in names
    assert "upload_post_images" in names
    assert "reprocess_post" in names
    assert "run_scheduler_task" in names
    assert "follow_list_status" in names
    assert "follow_list_member" in names
    assert "follow_list_refresh" in names
    assert "reprocess_errors" in names
  end

  test "exposes status and sources resources" do
    {:ok, resources, nil, _state} = Server.handle_list_resources(nil, %{})
    uris = Enum.map(resources, & &1.uri)

    assert "rss2nostr://status" in uris
    assert "rss2nostr://sources" in uris
    assert "rss2nostr://follow_list" in uris
  end
end
