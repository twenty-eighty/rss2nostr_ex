defmodule Rss2Nostr.Nostr.RelaysTest do
  use Rss2Nostr.DataCase

  alias Rss2Nostr.Nostr.Relays
  alias Rss2Nostr.Posts
  alias Rss2Nostr.Posts.Post
  alias Rss2Nostr.Sources

  @hex "0000000000000000000000000000000000000000000000000000000000000001"
  @author "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"

  setup do
    original = Application.get_env(:rss2nostr, :nostr)

    on_exit(fn ->
      Application.put_env(:rss2nostr, :nostr, original)
    end)

    :ok
  end

  defp put_relays(relays, audience \\ :test) do
    nostr = Application.get_env(:rss2nostr, :nostr, [])

    Application.put_env(
      :rss2nostr,
      :nostr,
      nostr
      |> Keyword.put(:relays, relays)
      |> Keyword.put(:relay_audience, audience)
    )
  end

  describe "test/0, public/0, draft/0, and inbox/0" do
    test "reads all lists from config" do
      put_relays(%{
        draft: ["wss://draft.example"],
        test: ["wss://test.example"],
        public: ["wss://public.example"],
        inbox: ["wss://inbox.example"]
      })

      assert Relays.draft() == ["wss://draft.example"]
      assert Relays.test() == ["wss://test.example"]
      assert Relays.public() == ["wss://public.example"]
      assert Relays.inbox() == ["wss://inbox.example"]
      assert Relays.for(:draft) == ["wss://draft.example"]
      assert Relays.for(:test) == ["wss://test.example"]
      assert Relays.for(:public) == ["wss://public.example"]
      assert Relays.for("public") == ["wss://public.example"]
      assert Relays.all().inbox == ["wss://inbox.example"]
    end

    test "treats a legacy list as the test list" do
      put_relays(["wss://legacy.example"])

      assert Relays.test() == ["wss://legacy.example"]
      assert Relays.public() == []
      assert Relays.draft() == []
      assert Relays.inbox() == []
    end

    test "falls back to the test list when draft relays are empty" do
      put_relays(%{draft: [], test: ["wss://test.example"], public: ["wss://public.example"]})

      assert Relays.draft() == []
      assert Relays.for(:draft) == ["wss://test.example"]
    end

    test "empty?/0 is true only when publish lists are empty" do
      put_relays(%{draft: [], test: [], public: [], inbox: []})
      assert Relays.empty?()

      put_relays(%{draft: [], test: [], public: [], inbox: ["wss://inbox.example"]})
      assert Relays.empty?()

      put_relays(%{draft: ["wss://draft.example"], test: [], public: []})
      refute Relays.empty?()

      put_relays(%{draft: [], test: ["wss://test.example"], public: []})
      refute Relays.empty?()
    end
  end

  describe "parse_audience/1" do
    test "accepts draft, test, and public" do
      assert Relays.parse_audience("draft") == :draft
      assert Relays.parse_audience("test") == :test
      assert Relays.parse_audience("public") == :public
      assert Relays.parse_audience(:public) == :public
      assert Relays.parse_audience("other") == nil
      assert Relays.parse_audience(nil) == nil
    end
  end

  describe "for_post/1" do
    test "uses the test list when the source is not public" do
      put_relays(%{test: ["wss://test.example"], public: ["wss://public.example"]})
      {:ok, source} = Sources.create_source(source_attrs(public: false))
      post = create_post(source)

      assert Relays.audience_for_post(post) == :test
      assert Relays.for_post(post) == ["wss://test.example"]
    end

    test "uses the public list when the source is automated and public" do
      put_relays(%{test: ["wss://test.example"], public: ["wss://public.example"]})
      {:ok, source} = Sources.create_source(source_attrs(public: true, mode: "automated"))
      post = create_post(source)

      assert Relays.audience_for_post(post) == :public
      assert Relays.for_post(post) == ["wss://public.example"]
    end

    test "uses the test list while a public source is still in setup" do
      put_relays(%{test: ["wss://test.example"], public: ["wss://public.example"]})
      {:ok, source} = Sources.create_source(source_attrs(public: true, mode: "setup"))
      post = create_post(source)

      assert Relays.audience_for_source(source) == :test
      assert Relays.for_post(post) == ["wss://test.example"]

      assert Relays.publish_relays(post, relays: ["wss://public.example"]) == [
               "wss://test.example"
             ]
    end

    test "preloads an unloaded source association" do
      put_relays(%{test: ["wss://test.example"], public: ["wss://public.example"]})
      {:ok, source} = Sources.create_source(source_attrs(public: true, mode: "automated"))
      post = create_post(source)
      unloaded = Posts.get_post(post.id)

      assert Relays.for_post(unloaded) == ["wss://public.example"]
    end

    test "uses the draft list for a draft source even when public and automated" do
      put_relays(%{
        draft: ["wss://draft.example"],
        test: ["wss://test.example"],
        public: ["wss://public.example"]
      })

      nostr = Application.get_env(:rss2nostr, :nostr, [])

      Application.put_env(
        :rss2nostr,
        :nostr,
        Keyword.put(nostr, :private_key, @hex)
      )

      {:ok, source} =
        Sources.create_source(
          source_attrs(public: true, mode: "automated")
          |> Map.merge(%{publish_as: "draft", pubkey: @author, signing_nsec: nil})
        )

      post = create_post(source)

      assert Relays.audience_for_post(post) == :public
      assert Relays.target_for(post) == :draft
      assert Relays.for_post(post) == ["wss://draft.example"]
      assert Relays.publish_relays(post, audience: :public) == ["wss://draft.example"]
    end

    test "uses the draft list for an unencrypted draft source" do
      put_relays(%{
        draft: ["wss://draft.example"],
        test: ["wss://test.example"],
        public: ["wss://public.example"]
      })

      {:ok, source} =
        Sources.create_source(
          source_attrs([])
          |> Map.merge(%{publish_as: "draft_plain", pubkey: @author, signing_nsec: nil})
        )

      post = create_post(source)

      assert Relays.target_for(post) == :draft
      assert Relays.for_post(post) == ["wss://draft.example"]
    end

    test "falls back to test relays when a draft source has no draft list" do
      put_relays(%{draft: [], test: ["wss://test.example"], public: ["wss://public.example"]})

      {:ok, source} =
        Sources.create_source(
          source_attrs([])
          |> Map.merge(%{publish_as: "draft", pubkey: @author, signing_nsec: nil})
        )

      post = create_post(source)

      assert Relays.for_post(post) == ["wss://test.example"]
    end
  end

  defp source_attrs(opts) do
    mode = Keyword.get(opts, :mode, "setup")

    %{
      name: "Relays Test Source",
      url: "https://example.com/relays-#{System.unique_integer([:positive])}.xml",
      type: "rss",
      language: "en",
      active: true,
      public: Keyword.get(opts, :public, false),
      mode: mode,
      publish_as: "article",
      signing_nsec: "0000000000000000000000000000000000000000000000000000000000000001"
    }
  end

  defp create_post(source) do
    url = "https://example.com/article-#{System.unique_integer([:positive])}"

    {:ok, post} =
      Posts.create_post(%{
        title: "Relay Test Article",
        source_url: url,
        source_url_hash: Post.generate_url_hash(url),
        source_html: "<p>Content</p>",
        status: Post.status_processed(),
        source_id: source.id
      })

    Posts.get_post(post.id, preload: [:source])
  end
end
