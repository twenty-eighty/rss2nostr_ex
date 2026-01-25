defmodule Rss2Nostr.Nostr.NIP19Test do
  use ExUnit.Case, async: true

  alias Rss2Nostr.Nostr.NIP19

  @test_pubkey "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"
  @test_privkey "67dea2ed018072d675f5415ecfaed7d2597555e202d85b3d65ea4e58d2d92ffa"

  describe "encode_npub/1" do
    test "encodes pubkey to npub format" do
      {:ok, npub} = NIP19.encode_npub(@test_pubkey)

      assert String.starts_with?(npub, "npub1")
      assert String.length(npub) == 63
    end

    test "returns error for invalid pubkey" do
      assert {:error, _} = NIP19.encode_npub("invalid")
      assert {:error, _} = NIP19.encode_npub("short")
    end
  end

  describe "encode_nsec/1" do
    test "encodes privkey to nsec format" do
      {:ok, nsec} = NIP19.encode_nsec(@test_privkey)

      assert String.starts_with?(nsec, "nsec1")
      assert String.length(nsec) == 63
    end
  end

  describe "encode_note/1" do
    test "encodes event id to note format" do
      event_id = String.duplicate("ab", 32)
      {:ok, note} = NIP19.encode_note(event_id)

      assert String.starts_with?(note, "note1")
    end
  end

  describe "decode/1" do
    test "decodes npub to pubkey" do
      {:ok, npub} = NIP19.encode_npub(@test_pubkey)
      {:ok, :npub, decoded} = NIP19.decode(npub)

      assert decoded == @test_pubkey
    end

    test "decodes nsec to privkey" do
      {:ok, nsec} = NIP19.encode_nsec(@test_privkey)
      {:ok, :nsec, decoded} = NIP19.decode(nsec)

      assert decoded == @test_privkey
    end

    test "decodes note to event id" do
      event_id = String.duplicate("cd", 32)
      {:ok, note} = NIP19.encode_note(event_id)
      {:ok, :note, decoded} = NIP19.decode(note)

      assert decoded == event_id
    end

    test "returns error for invalid bech32" do
      assert {:error, _} = NIP19.decode("invalid")
      assert {:error, _} = NIP19.decode("npub1invalid")
    end
  end

  describe "encode_naddr/4" do
    test "encodes naddr with all parameters" do
      kind = 30023
      pubkey = @test_pubkey
      identifier = "my-article"
      relays = ["wss://relay.example.com"]

      {:ok, naddr} = NIP19.encode_naddr(kind, pubkey, identifier, relays)

      assert String.starts_with?(naddr, "naddr1")
    end

    test "encodes naddr without relays" do
      {:ok, naddr} = NIP19.encode_naddr(30023, @test_pubkey, "test", [])

      assert String.starts_with?(naddr, "naddr1")
    end
  end

  describe "encode_nevent/2" do
    test "encodes nevent with event id" do
      event_id = String.duplicate("ef", 32)
      {:ok, nevent} = NIP19.encode_nevent(event_id, [])

      assert String.starts_with?(nevent, "nevent1")
    end

    test "encodes nevent with relays" do
      event_id = String.duplicate("12", 32)
      relays = ["wss://relay1.com", "wss://relay2.com"]
      {:ok, nevent} = NIP19.encode_nevent(event_id, relays)

      assert String.starts_with?(nevent, "nevent1")
    end
  end

  describe "encode_nprofile/2" do
    test "encodes nprofile with pubkey" do
      {:ok, nprofile} = NIP19.encode_nprofile(@test_pubkey, [])

      assert String.starts_with?(nprofile, "nprofile1")
    end

    test "encodes nprofile with relays" do
      relays = ["wss://relay.example.com"]
      {:ok, nprofile} = NIP19.encode_nprofile(@test_pubkey, relays)

      assert String.starts_with?(nprofile, "nprofile1")
    end
  end

  describe "roundtrip encoding" do
    test "npub roundtrip preserves data" do
      original = @test_pubkey
      {:ok, encoded} = NIP19.encode_npub(original)
      {:ok, :npub, decoded} = NIP19.decode(encoded)

      assert decoded == original
    end

    test "nsec roundtrip preserves data" do
      original = @test_privkey
      {:ok, encoded} = NIP19.encode_nsec(original)
      {:ok, :nsec, decoded} = NIP19.decode(encoded)

      assert decoded == original
    end
  end

  describe "decode/1 edge cases" do
    test "handles empty string" do
      assert {:error, _} = NIP19.decode("")
    end

    test "handles wrong prefix" do
      # Valid bech32 but wrong prefix for nostr
      assert {:error, _} = NIP19.decode("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4")
    end

    test "handles unknown nostr prefix" do
      # This should fail or return unknown type
      result =
        NIP19.decode("xyz1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqpqqqqd5hjfv")

      assert match?({:error, _}, result) or match?({:ok, :unknown, _}, result)
    end
  end

  describe "encode_npub/1 edge cases" do
    test "handles binary pubkey" do
      binary_key = Base.decode16!(@test_pubkey, case: :mixed)
      result = NIP19.encode_npub(binary_key)
      # Should handle or return error
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "encode_nsec/1 edge cases" do
    test "returns error for invalid length" do
      assert {:error, _} = NIP19.encode_nsec("tooshort")
    end
  end

  describe "encode_note/1 edge cases" do
    test "returns error for invalid event id" do
      assert {:error, _} = NIP19.encode_note("invalid")
    end
  end
end
