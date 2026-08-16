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

  test "staging message mentions hold hours for automated sources" do
    source = %Source{name: "Forum", mode: "automated", staging_hold_minutes: 360}
    post = %Post{title: "Part II", source_url: "https://example.com/ii"}

    message = StagingNotify.message(post, source)

    assert message =~ "Staging: Forum"
    assert message =~ "Part II"
    assert message =~ "https://example.com/ii"
    assert message =~ "Auto-publishes in 6h."
  end

  test "staging message waits for manual publish on setup sources" do
    source = %Source{name: "Forum", mode: "setup", staging_hold_minutes: 60}
    post = %Post{title: "Draft", source_url: "https://example.com/d"}

    assert StagingNotify.message(post, source) =~ "Waiting for manual publish."
  end
end
