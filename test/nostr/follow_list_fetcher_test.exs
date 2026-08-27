defmodule Rss2Nostr.Nostr.FollowList.FetcherTest do
  use ExUnit.Case, async: true

  alias Rss2Nostr.Nostr.FollowList.Fetcher

  @author "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
  @other "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

  test "members_from_event/1 extracts lowercase p-tag pubkeys" do
    event = %{
      "created_at" => 10,
      "tags" => [
        ["p", String.upcase(@author)],
        ["p", @other, "wss://relay.example.com"],
        ["relays", "wss://relay.example.com"],
        ["t", "follows"]
      ]
    }

    assert Fetcher.members_from_event(event) == MapSet.new([@author, @other])
  end

  test "fetch/2 uses the latest kind-3 event" do
    query = fn _urls, _filter ->
      [
        %{
          "id" => "old",
          "created_at" => 1,
          "tags" => [["p", @other]]
        },
        %{
          "id" => "new",
          "created_at" => 99,
          "tags" => [["p", @author]]
        }
      ]
    end

    assert {:ok, members} = Fetcher.fetch(@author, query: query, relays: ["wss://relay.example.com"])
    assert members == MapSet.new([@author])
  end

  test "fetch/2 returns an empty set when no contact list exists" do
    query = fn _urls, _filter -> [] end

    assert {:ok, members} = Fetcher.fetch(@author, query: query, relays: ["wss://relay.example.com"])
    assert members == MapSet.new()
  end
end
