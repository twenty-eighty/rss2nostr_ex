defmodule Rss2Nostr.Nostr.NIP44Test do
  use ExUnit.Case, async: true

  alias Rss2Nostr.Nostr.{Keys, NIP44}

  @private_key <<1::256>>

  test "encrypts and decrypts a payload to the signer's own pubkey" do
    pubkey = @private_key |> Keys.derive_public_key() |> Keys.to_hex()
    plaintext = ~s({"kind":30023,"content":"Hello draft"})

    assert {:ok, ciphertext} = NIP44.encrypt(plaintext, @private_key, pubkey)
    refute ciphertext == plaintext
    assert {:ok, ^plaintext} = NIP44.decrypt(ciphertext, @private_key, pubkey)
  end
end
