defmodule Rss2Nostr.Nostr.SignerTest do
  use Rss2Nostr.DataCase

  alias Rss2Nostr.Nostr.{Secret, Signer}
  alias Rss2Nostr.Sources
  alias Rss2Nostr.Sources.Source

  @hex "0000000000000000000000000000000000000000000000000000000000000001"

  test "encrypts and decrypts a source nsec" do
    cipher = Secret.encrypt("nsec-test")
    refute cipher == "nsec-test"
    assert {:ok, "nsec-test"} = Secret.decrypt(cipher)
  end

  test "resolves an article source from its encrypted nsec" do
    {:ok, source} =
      Sources.create_source(%{
        name: "Signer Source",
        url: "https://example.com/signer-#{System.unique_integer([:positive])}.xml",
        type: "rss",
        language: "en",
        publish_as: "article",
        signing_nsec: @hex
      })

    assert Signer.publish_as(source) == "article"
    assert Signer.signing_nsec_configured?(source)
    assert {:ok, {:private_key, key}} = Signer.resolve(source)
    assert byte_size(key) == 32
  end

  test "resolves an article source from a bunker URL" do
    source = %Source{
      publish_as: "article",
      bunker_connection: "bunker://abc?relay=wss://relay.example"
    }

    assert {:ok, {:bunker, "bunker://abc?relay=wss://relay.example"}} = Signer.resolve(source)
  end

  test "author_pubkey/1 prefers the stored author pubkey for drafts" do
    source = %Source{
      publish_as: "draft",
      pubkey: "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
    }

    assert Signer.author_pubkey(source) ==
             "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
  end

  test "author_pubkey/1 uses the stored pubkey for articles when present" do
    stored = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

    source = %Source{
      publish_as: "article",
      pubkey: stored,
      signing_nsec_ciphertext: "present-but-not-used-for-display"
    }

    assert Signer.author_pubkey(source) == stored
  end

  test "author_pubkey/1 derives the pubkey from a source nsec" do
    {:ok, source} =
      Sources.create_source(%{
        name: "Author Pubkey Source",
        url: "https://example.com/author-#{System.unique_integer([:positive])}.xml",
        type: "rss",
        language: "en",
        publish_as: "article",
        signing_nsec: @hex
      })

    assert Signer.author_pubkey(source) ==
             "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
  end

  test "draft sources need the app key" do
    source = %Source{publish_as: "draft"}
    assert {:error, :no_app_private_key} = Signer.resolve(source)
    assert {:ok, {:private_key, _}} = Signer.resolve(source, private_key: @hex)

    plain = %Source{publish_as: "draft_plain"}
    assert Signer.plain_draft?(plain)
    assert {:ok, {:private_key, _}} = Signer.resolve(plain, private_key: @hex)
  end

  test "upload_signer/1 prefers a source nsec over the app key" do
    {:ok, source} =
      Sources.create_source(%{
        name: "Upload Nsec Source",
        url: "https://example.com/upload-nsec-#{System.unique_integer([:positive])}.xml",
        type: "rss",
        language: "en",
        publish_as: "article",
        signing_nsec: @hex
      })

    assert {:ok, {:private_key, key}} = Signer.upload_signer(source)
    assert byte_size(key) == 32
  end

  test "upload_signer/1 uses a bunker URL when no source nsec is set" do
    source = %Source{
      publish_as: "article",
      bunker_connection: "bunker://abc?relay=wss://relay.example"
    }

    assert {:ok, {:bunker, "bunker://abc?relay=wss://relay.example"}} =
             Signer.upload_signer(source)
  end

  test "upload_signer/1 falls back to the app key only for drafts with a pubkey" do
    original = Application.get_env(:rss2nostr, :nostr)

    on_exit(fn ->
      Application.put_env(:rss2nostr, :nostr, original)
    end)

    nostr = Application.get_env(:rss2nostr, :nostr, [])
    Application.put_env(:rss2nostr, :nostr, Keyword.put(nostr, :private_key, @hex))

    draft = %Source{publish_as: "draft"}
    assert {:error, :no_source_pubkey} = Signer.upload_signer(draft)

    draft_with_pubkey = %Source{
      publish_as: "draft",
      pubkey: "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
    }

    assert {:ok, {:private_key, key}} = Signer.upload_signer(draft_with_pubkey)
    assert byte_size(key) == 32

    article = %Source{publish_as: "article"}
    assert {:error, :no_source_signer} = Signer.upload_signer(article)

    plain = %Source{publish_as: "draft_plain"}
    assert {:ok, {:private_key, _}} = Signer.upload_signer(plain)
  end

  test "app_signer/0 reads the configured NOSTR_NSEC" do
    original = Application.get_env(:rss2nostr, :nostr)

    on_exit(fn ->
      Application.put_env(:rss2nostr, :nostr, original)
    end)

    nostr = Application.get_env(:rss2nostr, :nostr, [])
    Application.put_env(:rss2nostr, :nostr, Keyword.put(nostr, :private_key, @hex))

    assert {:ok, {:private_key, key}} = Signer.app_signer()
    assert byte_size(key) == 32
  end
end
