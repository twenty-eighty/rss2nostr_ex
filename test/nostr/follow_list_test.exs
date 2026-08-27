defmodule Rss2Nostr.Nostr.FollowListTest do
  use ExUnit.Case, async: false

  alias Rss2Nostr.Nostr.FollowList

  @owner "0000000000000000000000000000000000000000000000000000000000000001"
  @followed "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
  @other "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

  setup do
    original = Application.get_env(:rss2nostr, :nostr)

    on_exit(fn ->
      Application.put_env(:rss2nostr, :nostr, original)
      _ = FollowList.refresh_sync()
    end)

    nostr = Keyword.merge(original || [], authors_follow_list_pubkey: @owner)

    nostr =
      Keyword.put(nostr, :follow_list_fetch, fn _ ->
        {:ok, MapSet.new([@followed])}
      end)

    Application.put_env(:rss2nostr, :nostr, nostr)
    :ok = FollowList.refresh_sync()
    :ok
  end

  test "configured?/0 and status/0 reflect the configured pubkey" do
    assert FollowList.configured?()
    status = FollowList.status()
    assert status.configured
    assert status.pubkey == @owner
    assert status.count == 1
    assert status.fetched_at
    assert is_nil(status.error)
  end

  test "member?/1 checks pubkeys against the cached follow list" do
    assert FollowList.member?(@followed)
    refute FollowList.member?(@other)
    refute FollowList.member?(nil)
  end

  test "members/0 returns sorted pubkey list" do
    assert FollowList.members() == [@followed]
  end

  test "membership_for_source/1 resolves author pubkey membership" do
    source = %{publish_as: "article", pubkey: @followed}
    assert FollowList.membership_for_source(source)

    refute FollowList.membership_for_source(%{publish_as: "article", pubkey: @other})
    assert FollowList.membership_for_source(%{publish_as: "draft", pubkey: nil}) == nil
  end

  test "source_membership_map/1 encodes membership for APIs" do
    assert FollowList.source_membership_map(%{publish_as: "article", pubkey: @followed}) == %{
             configured: true,
             member: true
           }
  end

  test "status/0 returns immediately while a refresh is in progress" do
    original = Application.get_env(:rss2nostr, :nostr)

    nostr =
      Keyword.merge(original || [],
        authors_follow_list_pubkey: @owner,
        follow_list_fetch: fn _ ->
          Process.sleep(500)
          {:ok, MapSet.new([@followed])}
        end
      )

    Application.put_env(:rss2nostr, :nostr, nostr)
    assert :ok = FollowList.refresh()

    assert FollowList.status().refreshing
    assert FollowList.configured?()
    assert :ok = FollowList.refresh_sync(5_000)
    refute FollowList.status().refreshing
  end
end
