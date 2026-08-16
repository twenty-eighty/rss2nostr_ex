defmodule Rss2Nostr.Nostr.NIP05Test do
  use ExUnit.Case, async: true

  alias Rss2Nostr.Nostr.NIP05

  @pubkey "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"

  test "parses a name@domain identifier" do
    assert {:ok, "bob", "example.com"} = NIP05.parse_identifier("Bob@Example.com")
    assert :error = NIP05.parse_identifier("not-an-identifier")
    assert :error = NIP05.parse_identifier("bob@localhost")
  end

  test "builds the well-known URL" do
    assert NIP05.well_known_url("bob", "example.com") ==
             "https://example.com/.well-known/nostr.json?name=bob"
  end

  test "returns relays only when the name maps to the pubkey" do
    document = %{
      "names" => %{"bob" => @pubkey},
      "relays" => %{
        @pubkey => ["wss://inbox.example.com", "https://not-a-relay.example", ""]
      }
    }

    assert NIP05.relays_for(document, "bob", String.upcase(@pubkey)) ==
             ["wss://inbox.example.com"]

    assert NIP05.relays_for(document, "bob", String.duplicate("0", 64)) == []
    assert NIP05.relays_for(document, "alice", @pubkey) == []
  end
end
