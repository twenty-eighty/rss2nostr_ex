defmodule Rss2Nostr.Nostr.InboxRelaysTest do
  use ExUnit.Case, async: false

  alias Rss2Nostr.Nostr.InboxRelays

  @pubkey "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"

  setup do
    original = Application.get_env(:rss2nostr, :nostr)

    on_exit(fn ->
      InboxRelays.clear(@pubkey)
      Application.put_env(:rss2nostr, :nostr, original)
    end)

    InboxRelays.clear(@pubkey)

    nostr = Application.get_env(:rss2nostr, :nostr, [])

    Application.put_env(
      :rss2nostr,
      :nostr,
      Keyword.put(nostr, :relays, %{
        draft: ["wss://draft.example.com"],
        test: ["wss://test.example.com"],
        public: ["wss://public.example.com"],
        inbox: []
      })
    )

    :ok
  end

  test "uses NIP-05 relays advertised for the recipient" do
    profile = %{
      "content" => Jason.encode!(%{"nip05" => "bob@example.com"})
    }

    document = %{
      "names" => %{"bob" => @pubkey},
      "relays" => %{@pubkey => ["wss://inbox.example.com"]}
    }

    assert InboxRelays.for_pubkey(@pubkey,
             profile: profile,
             nip05_document: document,
             cache: false
           ) == ["wss://inbox.example.com"]
  end

  test "falls back to the public inbox list when NIP-05 has no relays" do
    profile = %{"content" => Jason.encode!(%{"nip05" => "bob@example.com"})}

    document = %{
      "names" => %{"bob" => @pubkey},
      "relays" => %{}
    }

    assert InboxRelays.for_pubkey(@pubkey,
             profile: profile,
             nip05_document: document,
             cache: false
           ) == ["wss://public.example.com"]
  end

  test "falls back to the public inbox list when there is no profile" do
    assert InboxRelays.for_pubkey(@pubkey, profile: nil, cache: false) ==
             ["wss://public.example.com"]
  end

  test "always appends the extra inbox list" do
    nostr = Application.get_env(:rss2nostr, :nostr, [])

    Application.put_env(
      :rss2nostr,
      :nostr,
      Keyword.put(nostr, :relays, %{
        draft: ["wss://draft.example.com"],
        test: ["wss://test.example.com"],
        public: ["wss://public.example.com"],
        inbox: ["wss://extra-dm.example.com", "wss://inbox.example.com"]
      })
    )

    profile = %{"content" => Jason.encode!(%{"nip05" => "bob@example.com"})}

    document = %{
      "names" => %{"bob" => @pubkey},
      "relays" => %{@pubkey => ["wss://inbox.example.com"]}
    }

    assert InboxRelays.for_pubkey(@pubkey,
             profile: profile,
             nip05_document: document,
             cache: false
           ) == ["wss://inbox.example.com", "wss://extra-dm.example.com"]

    assert InboxRelays.for_pubkey(@pubkey, profile: nil, cache: false) ==
             ["wss://public.example.com", "wss://extra-dm.example.com", "wss://inbox.example.com"]
  end

  test "appends extra inbox relays after a cache hit" do
    profile = %{"content" => Jason.encode!(%{"nip05" => "bob@example.com"})}

    document = %{
      "names" => %{"bob" => @pubkey},
      "relays" => %{@pubkey => ["wss://inbox.example.com"]}
    }

    assert InboxRelays.for_pubkey(@pubkey, profile: profile, nip05_document: document) ==
             ["wss://inbox.example.com"]

    nostr = Application.get_env(:rss2nostr, :nostr, [])

    Application.put_env(
      :rss2nostr,
      :nostr,
      Keyword.put(nostr, :relays, %{
        draft: ["wss://draft.example.com"],
        test: ["wss://test.example.com"],
        public: ["wss://public.example.com"],
        inbox: ["wss://extra-dm.example.com"]
      })
    )

    assert InboxRelays.for_pubkey(@pubkey,
             fetch_profile: fn _ -> raise "should not fetch" end
           ) == ["wss://inbox.example.com", "wss://extra-dm.example.com"]
  end

  test "caches the resolved inbox relays" do
    profile = %{"content" => Jason.encode!(%{"nip05" => "bob@example.com"})}

    document = %{
      "names" => %{"bob" => @pubkey},
      "relays" => %{@pubkey => ["wss://inbox.example.com"]}
    }

    assert InboxRelays.for_pubkey(@pubkey, profile: profile, nip05_document: document) ==
             ["wss://inbox.example.com"]

    assert InboxRelays.for_pubkey(@pubkey,
             fetch_profile: fn _ -> raise "should not fetch" end
           ) == ["wss://inbox.example.com"]
  end
end
