defmodule Rss2Nostr.Nostr.NIP17Test do
  use ExUnit.Case, async: true

  alias Rss2Nostr.Nostr.{Keys, NIP17, StagingNotify}
  alias Rss2Nostr.Posts.Post
  alias Rss2Nostr.Sources.Source

  @sender <<1::256>>
  @recipient <<2::256>>

  test "wraps a kind 14 rumor in a NIP-44 seal and gift wrap" do
    recipient = @recipient |> Keys.derive_public_key() |> Keys.to_hex()

    assert {:ok, wrap} = NIP17.wrap("Hello staging", @sender, recipient, subject: "Staging")
    assert wrap.kind == 1059
    assert ["p", ^recipient] = Enum.find(wrap.tags, fn [tag | _] -> tag == "p" end)

    assert {:ok, rumor} = NIP17.unwrap(wrap, @recipient)
    assert rumor["kind"] == 14
    assert rumor["content"] == "Hello staging"
    assert rumor["tags"] == [["p", recipient], ["subject", "Staging"]]
    refute Map.has_key?(rumor, "sig")
  end

  test "staging message waits for manual publish on setup sources" do
    source = %Source{name: "Forum", mode: "setup", staging_hold_minutes: 60}
    post = %Post{title: "Draft", source_url: "https://example.com/d"}

    message = StagingNotify.message(post, source, :staging)

    assert message =~ "Staging: Forum"
    assert message =~ "Draft"
    assert message =~ "https://example.com/d"
    assert message =~ "Waiting for manual publish."
  end

  test "published message includes naddr for automated sources" do
    source = %Source{name: "Forum", mode: "automated", staging_hold_minutes: 360}

    post = %Post{
      title: "Part II",
      source_url: "https://example.com/ii",
      nostr_address: "naddr1qq…"
    }

    message = StagingNotify.message(post, source, :published)

    assert message =~ "Published: Forum"
    assert message =~ "Part II"
    assert message =~ "https://example.com/ii"
    assert message =~ "naddr1qq…"
  end

  test "maybe_notify_staging skips automated sources" do
    source = %Source{
      name: "Auto",
      mode: "automated",
      notify_pubkey: String.duplicate("a", 64)
    }

    post = %Post{id: 1, title: "T", source_url: "https://example.com", source: source}

    assert :ok = StagingNotify.maybe_notify_staging(post)
  end

  test "upload failed message says content upload failed" do
    source = %Source{name: "Forum", mode: "automated"}

    post = %Post{
      title: "Part II",
      source_url: "https://example.com/ii",
      last_error: "Media upload failed: download HTTP 403"
    }

    message = StagingNotify.message(post, source, :upload_failed)

    assert message =~ "Upload failed: Forum"
    assert message =~ "Part II"
    assert message =~ "https://example.com/ii"
    assert message =~ "Content/media upload failed."
    assert message =~ "download HTTP 403"
  end

  test "maybe_notify_upload_failed does not skip automated sources without a notify pubkey" do
    source = %Source{name: "Auto", mode: "automated", notify_pubkey: nil}
    post = %Post{id: 1, title: "T", source_url: "https://example.com", source: source}

    assert :ok = StagingNotify.maybe_notify_upload_failed(post)
  end

  test "maybe_notify_published skips setup sources" do
    source = %Source{
      name: "Setup",
      mode: "setup",
      notify_pubkey: String.duplicate("a", 64)
    }

    post = %Post{id: 1, title: "T", source_url: "https://example.com", source: source}

    assert :ok = StagingNotify.maybe_notify_published(post)
  end
end
