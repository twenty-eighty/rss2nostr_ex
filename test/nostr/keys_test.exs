defmodule Rss2Nostr.Nostr.KeysTest do
  use ExUnit.Case, async: true

  alias Rss2Nostr.Nostr.Keys
  alias Rss2Nostr.Nostr.NIP19

  describe "generate_private_key/0" do
    test "generates a 32-byte random key" do
      key = Keys.generate_private_key()
      assert byte_size(key) == 32
    end

    test "generates unique keys each time" do
      key1 = Keys.generate_private_key()
      key2 = Keys.generate_private_key()
      assert key1 != key2
    end
  end

  describe "derive_public_key/1" do
    test "derives public key from private key binary" do
      # Known test vector
      private_key = <<1::256>>
      pubkey = Keys.derive_public_key(private_key)

      assert is_binary(pubkey)
      assert byte_size(pubkey) == 32
    end

    test "derives public key from hex string" do
      private_key_hex = "0000000000000000000000000000000000000000000000000000000000000001"
      pubkey = Keys.derive_public_key(private_key_hex)

      assert is_binary(pubkey)
      assert byte_size(pubkey) == 32
    end

    test "derives consistent public key" do
      private_key = Keys.generate_private_key()
      pubkey1 = Keys.derive_public_key(private_key)
      pubkey2 = Keys.derive_public_key(private_key)

      assert pubkey1 == pubkey2
    end
  end

  describe "to_hex/1" do
    test "converts binary to lowercase hex" do
      binary = <<255, 0, 128>>
      hex = Keys.to_hex(binary)

      assert hex == "ff0080"
    end

    test "converts 32-byte key to 64-char hex" do
      key = Keys.generate_private_key()
      hex = Keys.to_hex(key)

      assert String.length(hex) == 64
      assert Regex.match?(~r/^[a-f0-9]+$/, hex)
    end
  end

  describe "from_hex/1" do
    test "converts hex to binary" do
      hex = "ff0080"
      {:ok, binary} = Keys.from_hex(hex)

      assert binary == <<255, 0, 128>>
    end

    test "handles uppercase hex" do
      {:ok, binary} = Keys.from_hex("FF0080")
      assert binary == <<255, 0, 128>>
    end

    test "returns error for invalid hex" do
      assert {:error, :invalid_hex} = Keys.from_hex("not_hex")
      assert {:error, :invalid_hex} = Keys.from_hex("gg00")
    end
  end

  describe "sha256/1" do
    test "computes correct SHA256 hash" do
      # Known test vector
      data = "hello"
      hash = Keys.sha256(data)

      expected =
        Base.decode16!("2CF24DBA5FB0A30E26E83B2AC5B9E29E1B161E5C1FA7425E73043362938B9824",
          case: :upper
        )

      assert hash == expected
    end

    test "returns 32-byte hash" do
      hash = Keys.sha256("test")
      assert byte_size(hash) == 32
    end
  end

  describe "valid_pubkey?/1" do
    test "returns true for valid 64-char hex pubkey" do
      pubkey = String.duplicate("a", 64)
      assert Keys.valid_pubkey?(pubkey)
    end

    test "returns false for invalid pubkey" do
      assert Keys.valid_pubkey?("short") == false
      assert Keys.valid_pubkey?("not_hex_" <> String.duplicate("0", 56)) == false
      assert Keys.valid_pubkey?(nil) == false
      assert Keys.valid_pubkey?(123) == false
    end
  end

  describe "parse_private_key/1" do
    test "parses hex format private key" do
      hex = String.duplicate("ab", 32)
      {:ok, binary} = Keys.parse_private_key(hex)

      assert byte_size(binary) == 32
    end

    test "parses nsec format private key" do
      # Generate a valid nsec for testing
      private_key = Keys.generate_private_key()
      {:ok, nsec} = NIP19.encode_nsec(Keys.to_hex(private_key))

      {:ok, parsed} = Keys.parse_private_key(nsec)
      assert parsed == private_key
    end

    test "returns error for invalid format" do
      assert {:error, :invalid_format} = Keys.parse_private_key("too_short")
      assert {:error, :invalid_input} = Keys.parse_private_key(nil)
    end
  end

  describe "parse_public_key/1" do
    test "parses hex public key" do
      hex = "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
      assert {:ok, ^hex} = Keys.parse_public_key(hex)
    end

    test "parses npub public key" do
      hex = "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
      {:ok, npub} = NIP19.encode_npub(hex)
      assert {:ok, ^hex} = Keys.parse_public_key(npub)
    end

    test "returns error for invalid input" do
      assert {:error, :invalid_format} = Keys.parse_public_key("nope")
      assert {:error, :invalid_input} = Keys.parse_public_key(nil)
    end
  end

  describe "parse_pubkey_list/1" do
    test "parses comma-separated hex and npub keys" do
      hex = "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
      {:ok, npub} = NIP19.encode_npub(hex)

      assert Keys.parse_pubkey_list("#{npub}, #{hex}, invalid") == [hex]
    end
  end

  describe "derive_public_key/1 edge cases" do
    test "returns error for invalid hex" do
      result = Keys.derive_public_key("not_valid_hex")
      assert result == {:error, :invalid_hex}
    end

    test "handles odd-length hex gracefully" do
      result = Keys.derive_public_key("abc")
      assert match?({:error, _}, result)
    end
  end

  describe "key format roundtrip" do
    test "hex roundtrip preserves key" do
      key = Keys.generate_private_key()
      hex = Keys.to_hex(key)
      {:ok, recovered} = Keys.from_hex(hex)

      assert key == recovered
    end

    test "derive_public_key works with hex and binary" do
      key = Keys.generate_private_key()
      hex = Keys.to_hex(key)

      pubkey_from_binary = Keys.derive_public_key(key)
      pubkey_from_hex = Keys.derive_public_key(hex)

      assert pubkey_from_binary == pubkey_from_hex
    end
  end

  describe "from_hex/1 edge cases" do
    test "handles empty string" do
      {:ok, binary} = Keys.from_hex("")
      assert binary == <<>>
    end

    test "returns error for odd-length hex" do
      result = Keys.from_hex("abc")
      assert match?({:error, _}, result)
    end
  end

  describe "valid_pubkey?/1 edge cases" do
    test "returns false for 32-byte binary (not hex)" do
      binary = Keys.generate_private_key()
      assert Keys.valid_pubkey?(binary) == false
    end

    test "returns true for valid lowercase hex" do
      pubkey = String.duplicate("0", 64)
      assert Keys.valid_pubkey?(pubkey) == true
    end

    test "returns true for valid mixed case hex" do
      pubkey = String.duplicate("aB", 32)
      assert Keys.valid_pubkey?(pubkey) == true
    end
  end
end
