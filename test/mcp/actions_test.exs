defmodule Rss2Nostr.MCP.ActionsTest do
  use Rss2Nostr.DataCase, async: false

  alias Rss2Nostr.MCP.Actions
  alias Rss2Nostr.Nostr.FollowList
  alias Rss2Nostr.Posts.Post
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

  test "get_settings includes compose presets" do
    assert {:ok, settings} = Actions.get_settings()
    assert is_map(settings.compose)
    assert settings.compose.body_presets != []
    assert settings.compose.languages != []
    assert settings.compose.publish_as == ~w(draft draft_plain article video)
  end

  test "add_source stores start_guid and compose options" do
    url = unique_url()

    assert {:ok, source} =
             Actions.add_source(%{
               name: "Compose MCP",
               url: url,
               language: "en",
               type: "rss",
               start_guid: "item-123",
               body_selector: "article.post",
               start_at: "//p[1]",
               skip_classes: "ad, promo",
               fetch_source_from: "content"
             })

    assert source.start_guid == "item-123"
    assert source.body_selector == "article.post"
    assert source.start_at == "//p[1]"
    assert source.skip_classes =~ "ad"
    assert source.fetch_source_from == "content"
  end

  test "update_source can set active flag" do
    {:ok, created} =
      Sources.create_source(%{
        name: "Mode MCP",
        url: unique_url(),
        type: "rss",
        language: "en",
        active: true
      })

    assert {:ok, updated} =
             Actions.update_source(%{
               source_id: created.id,
               active: false,
               name: "Renamed MCP"
             })

    assert updated.active == false
    assert updated.name == "Renamed MCP"
  end

  test "preview_compose requires a feed url" do
    assert {:error, "Feed URL is required"} = Actions.preview_compose(%{})
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

  describe "follow list" do
    @owner "0000000000000000000000000000000000000000000000000000000000000001"
    @followed "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"

    setup do
      original = Application.get_env(:rss2nostr, :nostr)

      on_exit(fn ->
        Application.put_env(:rss2nostr, :nostr, original)
        _ = FollowList.refresh_sync()
      end)

      nostr =
        Keyword.merge(original || [],
          authors_follow_list_pubkey: @owner,
          follow_list_fetch: fn _ -> {:ok, MapSet.new([@followed])} end
        )

      Application.put_env(:rss2nostr, :nostr, nostr)
      :ok = FollowList.refresh_sync()
      :ok
    end

    test "follow_list_status returns cache metadata" do
      assert {:ok, status} = Actions.follow_list_status(%{})
      assert status.configured
      assert status.count == 1
      refute Map.has_key?(status, :members)
    end

    test "follow_list_status can include members" do
      assert {:ok, status} = Actions.follow_list_status(%{include_members: true})
      assert status.members == [@followed]
    end

    test "follow_list_refresh starts a background refresh" do
      assert {:ok, status} = Actions.follow_list_refresh()
      assert status.configured
      assert is_boolean(status.refreshing)
    end

    test "follow_list_member checks pubkey and source_id" do
      assert {:ok, result} = Actions.follow_list_member(%{pubkey: @followed})
      assert result.member

      {:ok, source} =
        Sources.create_source(%{
          name: "Follow MCP",
          url: unique_url(),
          type: "rss",
          language: "en",
          publish_as: "draft",
          pubkey: @followed
        })

      assert {:ok, by_source} = Actions.follow_list_member(%{source_id: source.id})
      assert by_source.member
      assert by_source.author_pubkey == @followed
    end

    test "get_source and list_sources include follow_list membership" do
      {:ok, source} =
        Sources.create_source(%{
          name: "Follow List MCP",
          url: unique_url(),
          type: "rss",
          language: "en",
          publish_as: "draft",
          pubkey: @followed
        })

      assert {:ok, detail} = Actions.get_source(%{source_id: source.id})
      assert detail.follow_list == %{configured: true, member: true}

      assert {:ok, %{sources: sources}} = Actions.list_sources()
      listed = Enum.find(sources, &(&1.id == source.id))
      assert listed.follow_list == %{configured: true, member: true}
      assert listed.author_pubkey == @followed
    end
  end

  describe "reprocess_errors" do
    setup do
      {:ok, source} =
        Sources.create_source(%{
          name: "Error MCP",
          url: unique_url(),
          type: "rss",
          language: "en"
        })

      {:ok, post} =
        Rss2Nostr.Posts.create_post(%{
          source_id: source.id,
          title: "Failed article",
          source_url: "https://example.com/failed",
          source_url_hash: Post.generate_url_hash("https://example.com/failed"),
          status: Post.status_error(),
          last_error: "conversion failed"
        })

      %{source: source, post: post}
    end

    test "reprocesses all error posts", %{post: post} do
      assert {:ok, result} = Actions.reprocess_errors(%{})
      assert post.id in result.post_ids
      assert is_integer(result.processed)
      assert is_integer(result.errors)
    end

    test "reprocesses error posts for one source", %{source: source, post: post} do
      assert {:ok, result} = Actions.reprocess_errors(%{source_id: source.id})
      assert post.id in result.post_ids
    end
  end

  test "post responses include reprocessable and publishable flags" do
    {:ok, source} =
      Sources.create_source(%{
        name: "Flags MCP",
        url: unique_url(),
        type: "rss",
        language: "en"
      })

    {:ok, error_post} =
      Rss2Nostr.Posts.create_post(%{
        source_id: source.id,
        title: "Error",
        source_url: "https://example.com/e",
        source_url_hash: Post.generate_url_hash("https://example.com/e"),
        status: Post.status_error()
      })

    {:ok, staging_post} =
      Rss2Nostr.Posts.create_post(%{
        source_id: source.id,
        title: "Staging",
        source_url: "https://example.com/s",
        source_url_hash: Post.generate_url_hash("https://example.com/s"),
        status: Post.status_processed()
      })

    assert {:ok, error} = Actions.get_post(%{post_id: error_post.id})
    assert error.reprocessable
    refute error.publishable

    assert {:ok, staging} = Actions.get_post(%{post_id: staging_post.id})
    assert staging.reprocessable
    assert staging.publishable
  end
end
