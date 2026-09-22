defmodule Rss2Nostr.Import.ImporterTest do
  use Rss2Nostr.DataCase

  alias Rss2Nostr.Import.Importer
  alias Rss2Nostr.Posts
  alias Rss2Nostr.Posts.Post
  alias Rss2Nostr.Sources

  def unique_url do
    "https://example.com/feed-#{System.unique_integer([:positive])}.xml"
  end

  describe "import_all/1" do
    test "returns empty list when no active sources" do
      result = Importer.import_all()

      assert is_list(result)
    end

    test "processes active sources" do
      {:ok, _source} =
        Sources.create_source(%{
          name: "Import Test Source",
          url: unique_url(),
          type: "rss",
          language: "en",
          active: true
        })

      result = Importer.import_all()

      assert is_list(result)
      # Each result should have the expected structure
      Enum.each(result, fn r ->
        assert Map.has_key?(r, :source)
        assert Map.has_key?(r, :imported)
        assert Map.has_key?(r, :skipped)
        assert Map.has_key?(r, :errors)
      end)
    end
  end

  describe "import_from_source/2" do
    test "returns result structure with source" do
      {:ok, source} =
        Sources.create_source(%{
          name: "Direct Import Test",
          url: unique_url(),
          type: "rss",
          language: "en",
          active: true
        })

      result = Importer.import_from_source(source)

      assert result.source.id == source.id
      assert is_integer(result.imported)
      assert is_integer(result.skipped)
      assert is_list(result.errors)
    end

    test "handles fetch errors gracefully" do
      {:ok, source} =
        Sources.create_source(%{
          name: "Bad URL Source",
          url: "https://nonexistent.invalid/feed.xml",
          type: "rss",
          language: "en",
          active: true
        })

      result = Importer.import_from_source(source)

      assert result.source.id == source.id
      assert result.errors != []
    end
  end

  describe "import_from_source_id/2" do
    test "imports from source by id" do
      {:ok, source} =
        Sources.create_source(%{
          name: "ID Import Test",
          url: unique_url(),
          type: "rss",
          language: "en",
          active: true
        })

      {:ok, result} = Importer.import_from_source_id(source.id)

      assert result.source.id == source.id
    end

    test "returns error for non-existent source" do
      assert {:error, :source_not_found} = Importer.import_from_source_id(999_999)
    end
  end

  describe "reimport_post/1" do
    test "downloads the article page again and reconverts it" do
      page_html = """
      <!DOCTYPE html>
      <html><head><title>Later</title></head>
      <body><p>Later video is up</p></body></html>
      """

      bandit =
        start_supervised!(
          {Bandit, plug: {__MODULE__.PageStub, page_html}, port: 0, ip: {127, 0, 0, 1}}
        )

      {:ok, {_ip, port}} = ThousandIsland.listener_info(bandit)
      page = "http://127.0.0.1:#{port}/whos-at-the-top"

      {:ok, source} =
        Sources.create_source(%{
          name: "Reimport Page",
          url: unique_url(),
          type: "rss",
          language: "en",
          active: true,
          fetch_source_from: "fetch_from_url"
        })

      {:ok, post} =
        Posts.create_post(%{
          title: "Who's At the Top?",
          source_url: page,
          source_url_hash: Post.generate_url_hash(page),
          source_html: "<p>Published before the player existed</p>",
          content: "Published before the player existed",
          status: Post.status_processed(),
          source_id: source.id
        })

      assert {:ok, updated} = Importer.reimport_post(post)
      assert updated.source_html =~ "Later video is up"
      assert updated.content =~ "Later video is up"
      refute updated.content =~ "before the player"
    end

    test "uses updated feed HTML when the source reads content from the feed" do
      agent = start_supervised!({Agent, fn -> %{page: 0, feed: 0} end})

      bandit =
        start_supervised!(
          {Bandit, plug: {__MODULE__.FeedStub, agent}, port: 0, ip: {127, 0, 0, 1}}
        )

      {:ok, {_ip, port}} = ThousandIsland.listener_info(bandit)
      base = "http://127.0.0.1:#{port}"
      page = "#{base}/article"

      {:ok, source} =
        Sources.create_source(%{
          name: "Reimport Feed",
          url: "#{base}/feed.xml",
          type: "rss",
          language: "en",
          active: true,
          fetch_source_from: "content"
        })

      {:ok, post} =
        Posts.create_post(%{
          title: "Feed article",
          article_identifier: page,
          source_url: page,
          source_url_hash: Post.generate_url_hash(page),
          source_html: "<p>Old feed body</p>",
          content: "Old feed body",
          status: Post.status_processed(),
          source_id: source.id
        })

      assert {:ok, updated} = Importer.reimport_post(post)
      assert updated.content =~ "Player from the feed"
      refute updated.content =~ "Page only"
      assert Agent.get(agent, & &1.feed) == 1
    end

    test "does not reimport a skipped article" do
      {:ok, source} =
        Sources.create_source(%{
          name: "Skipped Reimport",
          url: unique_url(),
          type: "rss",
          language: "en",
          active: true
        })

      url = "https://example.com/skipped-#{System.unique_integer([:positive])}"

      {:ok, post} =
        Posts.create_post(%{
          title: "Skipped",
          source_url: url,
          source_url_hash: Post.generate_url_hash(url),
          source_html: "<p>Keep</p>",
          status: Post.status_blocked(),
          source_id: source.id
        })

      assert {:error, :skipped} = Importer.reimport_post(post)
    end
  end

  defmodule PageStub do
    @moduledoc false
    @behaviour Plug

    def init(html), do: html

    def call(conn, html) do
      conn
      |> Plug.Conn.put_resp_content_type("text/html")
      |> Plug.Conn.send_resp(200, html)
    end
  end

  defmodule FeedStub do
    @moduledoc false
    @behaviour Plug

    def init(agent), do: agent

    def call(conn, agent) do
      key = if conn.request_path == "/feed.xml", do: :feed, else: :page
      Agent.update(agent, fn state -> Map.update(state, key, 1, &(&1 + 1)) end)

      body =
        if key == :feed do
          page = "#{conn.scheme}://#{conn.host}:#{conn.port}/article"

          """
          <?xml version="1.0"?>
          <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
            <channel>
              <item>
                <title>Feed article</title>
                <link>#{page}</link>
                <guid>#{page}</guid>
                <content:encoded><![CDATA[<p>Player from the feed</p>]]></content:encoded>
              </item>
            </channel>
          </rss>
          """
        else
          "<!DOCTYPE html><html><body><p>Page only</p></body></html>"
        end

      conn
      |> Plug.Conn.put_resp_content_type(
        if(key == :feed, do: "application/rss+xml", else: "text/html")
      )
      |> Plug.Conn.send_resp(200, body)
    end
  end
end
