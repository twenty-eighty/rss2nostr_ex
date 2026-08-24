defmodule Rss2Nostr.Nostr.PublisherTest do
  use Rss2Nostr.DataCase

  alias Rss2Nostr.Nostr.{Event, Publisher}
  alias Rss2Nostr.Posts
  alias Rss2Nostr.Posts.Post
  alias Rss2Nostr.Sources

  @hex "0000000000000000000000000000000000000000000000000000000000000001"
  @author "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"

  describe "preview_event/2" do
    test "builds an unsigned long-form EVENT message for a draft without a key" do
      preview =
        Publisher.preview_event(%{
          title: "Hello",
          content: "# Hello\n\nBody",
          summary: "A summary",
          image: "https://example.com/img.jpg",
          source_url: "https://example.com/hello",
          published_at: ~U[2024-01-15 12:00:00Z],
          type: 30024
        })

      event = preview.event
      assert event.kind == 30024
      assert event.content == "# Hello\n\nBody"
      assert event.pubkey == String.duplicate("0", 64)
      refute Map.has_key?(event, :id)
      refute Map.has_key?(event, :sig)
      refute preview.encrypted
      assert is_nil(preview.inner)
      assert ["title", "Hello"] in event.tags
      assert ["summary", "A summary"] in event.tags
      assert ["image", "https://example.com/img.jpg"] in event.tags
      assert ["published_at", "1705320000"] in event.tags
      assert ["r", "https://example.com/hello"] in event.tags
      assert preview.message == ["EVENT", event]
      assert preview.json =~ "\"EVENT\""
      assert preview.json =~ "\"kind\": 30024"
      assert preview.json =~ "\"content\":"
      refute preview.signed
      assert preview.relays == ["wss://nos.lol"]
    end

    test "uses inner kind 30024 and draft relays for a setup draft source" do
      {:ok, source} =
        Sources.create_source(%{
          name: "Preview Source",
          url: "https://example.com/preview-#{System.unique_integer([:positive])}.xml",
          type: "rss",
          language: "en",
          publish_as: "draft",
          pubkey: @author
        })

      url = "https://example.com/preview-article-#{System.unique_integer([:positive])}"

      {:ok, post} =
        Posts.create_post(%{
          title: "Preview Article",
          content: "Article body",
          source_url: url,
          source_url_hash: Post.generate_url_hash(url),
          status: Post.status_processed(),
          type: source.default_post_kind,
          source_id: source.id
        })

      post = Posts.get_post(post.id, preload: [:source])
      preview = Publisher.preview_event(post)

      assert preview.event.kind == 30024
      assert preview.event.content == "Article body"
      refute preview.encrypted
      assert ["title", "Preview Article"] in preview.event.tags
      assert ["p", @author] in preview.event.tags
      assert preview.relays == ["wss://draft.example.com"]
    end

    test "builds a kind 34235 video event with the original file URL" do
      {:ok, source} =
        Sources.create_source(%{
          name: "Video Source",
          url: "https://example.com/video-#{System.unique_integer([:positive])}.xml",
          type: "rss",
          language: "en",
          publish_as: "video",
          signing_nsec: @hex,
          options: %{"mirror_media" => "original"}
        })

      video = "https://www.corbettreport.com/mp4/nwnw640.mp4"

      {:ok, post} =
        Posts.create_post(%{
          title: "Guess Where They're Building Data Centres Now... (NWNW #640)",
          content: "[Video](#{video})\n\nThis week on New World Next Week.",
          summary: "This week on New World Next Week.",
          source_url: video,
          source_url_hash: Post.generate_url_hash(video),
          status: Post.status_processed(),
          type: 34235,
          source_id: source.id
        })

      {:ok, _} =
        Posts.create_image(%{
          post_id: post.id,
          original_url: video,
          uploaded_url: video,
          mime_type: "video/mp4",
          imeta: ["url #{video}", "m video/mp4", "duration 1423", "alt Video"]
        })

      post = Posts.get_post(post.id, preload: [:source, :images])
      preview = Publisher.preview_event(post)

      assert preview.event.kind == 34235
      assert ["title", post.title] in preview.event.tags
      assert ["alt", "This week on New World Next Week."] in preview.event.tags

      assert ["imeta", "url #{video}", "m video/mp4", "duration 1423", "alt Video"] in preview.event.tags

      refute preview.encrypted
    end

    test "adds imeta tags for uploaded media in the article" do
      {:ok, source} =
        Sources.create_source(%{
          name: "Imeta Source",
          url: "https://example.com/imeta-#{System.unique_integer([:positive])}.xml",
          type: "rss",
          language: "en",
          publish_as: "article",
          pubkey: @author,
          signing_nsec: @hex
        })

      url = "https://example.com/imeta-article-#{System.unique_integer([:positive])}"
      hero = "https://route96.example/hero.png"
      audio = "https://route96.example/show.mp3"

      {:ok, post} =
        Posts.create_post(%{
          title: "Imeta Article",
          content: "![Hero](#{hero})\n\n[Audio](#{audio})",
          image: hero,
          source_url: url,
          source_url_hash: Post.generate_url_hash(url),
          status: Post.status_processed(),
          type: 30023,
          source_id: source.id
        })

      {:ok, _} =
        Posts.create_image(%{
          post_id: post.id,
          original_url: "https://corbettreport.com/hero.png",
          uploaded_url: hero,
          mime_type: "image/png",
          sha256: "aa",
          dim: "1x1",
          imeta: ["url #{hero}", "m image/png", "x aa", "dim 1x1"]
        })

      {:ok, _} =
        Posts.create_image(%{
          post_id: post.id,
          original_url: "https://corbettreport.com/show.mp3",
          uploaded_url: audio,
          mime_type: "audio/mpeg",
          sha256: "bb",
          imeta: ["url #{audio}", "m audio/mpeg", "x bb"]
        })

      post = Posts.get_post(post.id, preload: [:source, :images])
      preview = Publisher.preview_event(post)

      assert ["imeta", "url #{hero}", "m image/png", "x aa", "dim 1x1"] in preview.event.tags
      assert ["imeta", "url #{audio}", "m audio/mpeg", "x bb"] in preview.event.tags
    end

    test "keeps the source author on the p tag after the wrap is published" do
      app_pubkey = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

      {:ok, source} =
        Sources.create_source(%{
          name: "Published Draft Source",
          url: "https://example.com/pub-draft-#{System.unique_integer([:positive])}.xml",
          type: "rss",
          language: "en",
          publish_as: "draft",
          pubkey: @author
        })

      url = "https://example.com/pub-draft-article-#{System.unique_integer([:positive])}"

      {:ok, post} =
        Posts.create_post(%{
          title: "Published Draft",
          content: "Body",
          source_url: url,
          source_url_hash: Post.generate_url_hash(url),
          status: Post.status_published(),
          type: 30024,
          pubkey: app_pubkey,
          source_id: source.id
        })

      post = Posts.get_post(post.id, preload: [:source])
      preview = Publisher.preview_event(post)

      assert ["p", @author] in preview.event.tags
      refute ["p", app_pubkey] in preview.event.tags
      assert preview.event.pubkey == @author
    end

    test "previews the inner article that will be NIP-44-encrypted" do
      original = Application.get_env(:rss2nostr, :nostr)

      on_exit(fn ->
        Application.put_env(:rss2nostr, :nostr, original)
      end)

      nostr = Application.get_env(:rss2nostr, :nostr, [])
      Application.put_env(:rss2nostr, :nostr, Keyword.put(nostr, :private_key, @hex))

      {:ok, source} =
        Sources.create_source(%{
          name: "Encrypted Draft Source",
          url: "https://example.com/enc-draft-#{System.unique_integer([:positive])}.xml",
          type: "rss",
          language: "en",
          publish_as: "draft",
          pubkey: @author,
          fixed_hashtags: ["#PatrikBaab", "bitcoin"]
        })

      url = "https://example.com/enc-draft-#{System.unique_integer([:positive])}"

      {:ok, post} =
        Posts.create_post(%{
          title: "Secret Draft",
          content: "Hidden body",
          source_url: url,
          source_url_hash: Post.generate_url_hash(url),
          status: Post.status_processed(),
          type: 30024,
          language: "en",
          categories: ["Nostr", "#Bitcoin", "PatrikBaab"],
          source_id: source.id
        })

      post = Posts.get_post(post.id, preload: [:source])
      preview = Publisher.preview_event(post)

      assert preview.draft
      refute preview.encrypted
      assert preview.event.kind == 30024
      assert preview.event.content == "Hidden body"
      assert ["p", @author] in preview.event.tags
      assert ["L", "ISO-639-1"] in preview.event.tags
      assert ["l", "en", "ISO-639-1"] in preview.event.tags
      t_tags = for ["t", tag] <- preview.event.tags, do: tag
      assert t_tags == ["patrikbaab", "bitcoin", "nostr"]
      assert ["r", url] in preview.event.tags
      assert length(preview.parts) == 1
    end

    test "drops excluded RSS categories from published hashtags" do
      {:ok, source} =
        Sources.create_source(%{
          name: "Radio Filter Source",
          url: "https://example.com/radio-filter-#{System.unique_integer([:positive])}.xml",
          type: "rss",
          language: "de",
          excluded_hashtags: ["ROOT", "Haupteintrag"]
        })

      url = "https://example.com/radio-filter-#{System.unique_integer([:positive])}"

      {:ok, post} =
        Posts.create_post(%{
          title: "Sommerpause",
          content: "Body",
          source_url: url,
          source_url_hash: Post.generate_url_hash(url),
          status: Post.status_processed(),
          type: 30024,
          language: "de",
          categories: ["Haupteintrag", "radiomuenchen", "ROOT", "Politik"],
          source_id: source.id
        })

      post = Posts.get_post(post.id, preload: [:source])
      preview = Publisher.preview_event(post)
      t_tags = for ["t", tag] <- preview.event.tags, do: tag

      assert t_tags == ["radiomuenchen", "politik"]
    end

    test "splits a draft whose wrap would exceed the relay event limit" do
      {:ok, source} =
        Sources.create_source(%{
          name: "Wrap Limit Source",
          url: "https://example.com/wrap-limit-#{System.unique_integer([:positive])}.xml",
          type: "rss",
          language: "en",
          publish_as: "draft",
          pubkey: @author
        })

      content =
        Enum.map_join(1..4, "\n\n", fn n ->
          "## Section #{n}\n\n#{String.duplicate("lorem ipsum dolor sit amet. ", 450)}"
        end)

      url = "https://example.com/wrap-limit-#{System.unique_integer([:positive])}"

      {:ok, post} =
        Posts.create_post(%{
          title: "Near the wrap limit",
          content: content,
          source_url: url,
          source_url_hash: Post.generate_url_hash(url),
          status: Post.status_processed(),
          type: 30024,
          source_id: source.id
        })

      post = Posts.get_post(post.id, preload: [:source])

      whole =
        Event.build_long_form(@author, content,
          title: "Near the wrap limit",
          identifier: "near-the-wrap-limit",
          author_pubkey: @author,
          kind: 30024
        )

      assert Event.draft_plaintext_size(whole) <= Event.max_draft_plaintext_size()

      assert Event.estimate_wrap_message_size(whole, author_pubkey: @author) >
               Event.max_event_size()

      preview = Publisher.preview_event(post)
      assert length(preview.parts) > 1

      Enum.each(preview.parts, fn event ->
        assert Event.estimate_wrap_message_size(event, author_pubkey: @author) <=
                 Event.max_event_size()
      end)
    end

    test "splits an oversized draft so each part fits NIP-44" do
      {:ok, source} =
        Sources.create_source(%{
          name: "Split Draft Source",
          url: "https://example.com/split-draft-#{System.unique_integer([:positive])}.xml",
          type: "rss",
          language: "en",
          publish_as: "draft",
          pubkey: @author
        })

      body = String.duplicate("lorem ipsum dolor sit amet. ", 2500)

      content =
        Enum.map_join(1..6, "\n\n", fn n ->
          "## Section #{n}\n\n#{body}"
        end)

      url = "https://example.com/split-#{System.unique_integer([:positive])}"

      {:ok, post} =
        Posts.create_post(%{
          title: "Huge Draft",
          content: content,
          summary: "A shared summary",
          image: "https://example.com/cover.jpg",
          source_url: url,
          source_url_hash: Post.generate_url_hash(url),
          published_at: ~U[2024-01-15 12:00:00Z],
          status: Post.status_processed(),
          type: 30024,
          source_id: source.id
        })

      post = Posts.get_post(post.id, preload: [:source])
      preview = Publisher.preview_event(post)
      max = Event.max_event_size()

      assert length(preview.parts) > 1
      assert ["title", "Huge Draft (1/#{length(preview.parts)})"] in preview.event.tags

      published_ats =
        Enum.map(preview.parts, fn event ->
          ["published_at", value] =
            Enum.find(event.tags, fn [tag | _] -> tag == "published_at" end)

          String.to_integer(value)
        end)

      Enum.with_index(preview.parts, 1)
      |> Enum.each(fn {event, index} ->
        assert event.kind == 30024
        assert Event.draft_plaintext_size(event) <= Event.max_draft_plaintext_size()
        assert Event.estimate_wrap_message_size(event, author_pubkey: @author) <= max
        assert ["title", "Huge Draft (#{index}/#{length(preview.parts)})"] in event.tags
        assert ["summary", "A shared summary"] in event.tags
        assert ["image", "https://example.com/cover.jpg"] in event.tags
      end)

      assert hd(published_ats) == 1_705_320_000

      assert published_ats ==
               Enum.to_list(1_705_320_000..(1_705_320_000 + length(preview.parts) - 1))
    end

    test "publishes unencrypted drafts as kind 30024 with an author p tag" do
      {:ok, source} =
        Sources.create_source(%{
          name: "Plain Draft Source",
          url: "https://example.com/plain-draft-#{System.unique_integer([:positive])}.xml",
          type: "rss",
          language: "en",
          publish_as: "draft_plain",
          pubkey: @author
        })

      url = "https://example.com/plain-draft-article-#{System.unique_integer([:positive])}"

      {:ok, post} =
        Posts.create_post(%{
          title: "Plain Draft",
          content: "Draft body",
          source_url: url,
          source_url_hash: Post.generate_url_hash(url),
          status: Post.status_processed(),
          type: 30024,
          source_id: source.id
        })

      post = Posts.get_post(post.id, preload: [:source])
      preview = Publisher.preview_event(post)

      assert preview.event.kind == 30024
      assert preview.plain_draft
      refute preview.draft
      refute preview.encrypted
      assert ["p", @author] in preview.event.tags
      assert preview.relays == ["wss://draft.example.com"]
    end

    test "publishes kind 30023 when the source is an article even if the post type is 30024" do
      {:ok, source} =
        Sources.create_source(%{
          name: "Switched Article Source",
          url: "https://example.com/switched-#{System.unique_integer([:positive])}.xml",
          type: "rss",
          language: "en",
          publish_as: "article",
          signing_nsec: @hex
        })

      url = "https://example.com/switched-#{System.unique_integer([:positive])}"

      {:ok, post} =
        Posts.create_post(%{
          title: "Was a draft",
          content: "Body",
          source_url: url,
          source_url_hash: Post.generate_url_hash(url),
          status: Post.status_processed(),
          type: 30024,
          source_id: source.id
        })

      post = Posts.get_post(post.id, preload: [:source])
      preview = Publisher.preview_event(post)

      assert preview.event.kind == 30023
      refute preview.draft
    end

    test "leaves articles as plaintext kind 30023" do
      {:ok, source} =
        Sources.create_source(%{
          name: "Article Source",
          url: "https://example.com/article-src-#{System.unique_integer([:positive])}.xml",
          type: "rss",
          language: "en",
          publish_as: "article",
          signing_nsec: @hex
        })

      url = "https://example.com/article-#{System.unique_integer([:positive])}"

      {:ok, post} =
        Posts.create_post(%{
          title: "Public Article",
          content: "Public body",
          source_url: url,
          source_url_hash: Post.generate_url_hash(url),
          status: Post.status_processed(),
          type: 30023,
          source_id: source.id
        })

      post = Posts.get_post(post.id, preload: [:source])
      preview = Publisher.preview_event(post)

      assert preview.event.kind == 30023
      assert preview.event.content == "Public body"
      refute preview.encrypted
      assert is_nil(preview.inner)
      refute Enum.any?(preview.event.tags, fn [tag | _] -> tag == "p" end)
      assert Event.pareto_client_tag() in preview.event.tags
    end

    test "adds the Pareto client tag on articles sent to public relays" do
      {:ok, source} =
        Sources.create_source(%{
          name: "Public Article Source",
          url: "https://example.com/public-src-#{System.unique_integer([:positive])}.xml",
          type: "rss",
          language: "en",
          publish_as: "article",
          public: true,
          mode: "automated",
          signing_nsec: @hex
        })

      url = "https://example.com/public-article-#{System.unique_integer([:positive])}"

      {:ok, post} =
        Posts.create_post(%{
          title: "Public Article",
          content: "Public body",
          source_url: url,
          source_url_hash: Post.generate_url_hash(url),
          status: Post.status_processed(),
          type: 30023,
          source_id: source.id
        })

      post = Posts.get_post(post.id, preload: [:source])
      preview = Publisher.preview_event(post)

      assert preview.event.kind == 30023
      assert Event.pareto_client_tag() in preview.event.tags
    end
  end

  describe "identifier/1" do
    test "uses the last non-empty path segment when the URL has a trailing slash" do
      assert Publisher.identifier(%{
               title: "August Open Thread 2026",
               source_url: "https://corbettreport.com/august-open-thread-2026/"
             }) == "august-open-thread-2026"
    end

    test "gives each trailing-slash URL its own d tag" do
      first =
        Publisher.identifier(%{
          title: "One",
          source_url:
            "https://corbettreport.com/under-the-bus-how-bill-gates-fell-from-globalist-grace/"
        })

      second =
        Publisher.identifier(%{
          title: "Two",
          source_url: "https://corbettreport.com/august-open-thread-2026/"
        })

      assert first == "under-the-bus-how-bill-gates-fell-from-globalist-grace"
      assert second == "august-open-thread-2026"
      refute first == second
    end

    test "falls back to the title when the path is only a slash" do
      assert Publisher.identifier(%{
               title: "Home Page",
               source_url: "https://example.com/"
             }) == "home-page"
    end
  end

  describe "each_with_gap/2" do
    test "maps items without sleeping when the gap is zero" do
      assert Publisher.publish_gap_ms() == 0
      assert Publisher.each_with_gap([1, 2, 3], &(&1 * 2)) == [2, 4, 6]
    end
  end

  describe "format_report/2" do
    test "lists accepted relays and per-relay failures" do
      report =
        Publisher.format_report(
          ["wss://client-test.pareto.space"],
          [
            %{url: "wss://client-test.pareto.town", error: "could not resolve host"}
          ]
        )

      assert report ==
               "Reached 1 relay: client-test.pareto.space. Missed 1: client-test.pareto.town (could not resolve host)."
    end

    test "reports a relay rejection without an accepted list" do
      report =
        Publisher.format_report([], [
          %{url: "wss://client-test.pareto.space", error: "invalid: event too large: 87959"}
        ])

      assert report == "Missed 1: client-test.pareto.space (invalid: event too large: 87959)."
    end
  end
end
