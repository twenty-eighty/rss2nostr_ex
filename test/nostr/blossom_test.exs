defmodule Rss2Nostr.Nostr.BlossomTest do
  use Rss2Nostr.DataCase, async: false

  alias Rss2Nostr.Nostr.Blossom
  alias Rss2Nostr.Posts
  alias Rss2Nostr.Posts.Post
  alias Rss2Nostr.Sources

  setup do
    original = Application.get_env(:rss2nostr, :nostr)

    on_exit(fn ->
      Application.put_env(:rss2nostr, :nostr, original)
    end)

    :ok
  end

  defp put_upload_endpoint(endpoint) do
    nostr = Application.get_env(:rss2nostr, :nostr, [])
    Application.put_env(:rss2nostr, :nostr, Keyword.put(nostr, :upload_endpoint, endpoint))
  end

  describe "configured_server/0" do
    test "reads NOSTR_UPLOAD_ENDPOINT via application env" do
      put_upload_endpoint("https://route96.example/")
      assert Blossom.configured_server() == "https://route96.example"
    end

    test "treats blank as unset" do
      put_upload_endpoint("  ")
      assert Blossom.configured_server() == nil
    end
  end

  describe "servers/0" do
    test "returns only the configured endpoint" do
      put_upload_endpoint("https://route96.example")
      assert Blossom.servers() == ["https://route96.example"]
    end

    test "returns an empty list when unset" do
      put_upload_endpoint(nil)
      assert Blossom.servers() == []
    end
  end

  describe "upload_url/1" do
    test "appends /upload" do
      assert Blossom.upload_url("https://cdn.example") == "https://cdn.example/upload"
      assert Blossom.upload_url("https://cdn.example/") == "https://cdn.example/upload"
      assert Blossom.upload_url("https://cdn.example/upload") == "https://cdn.example/upload"
    end
  end

  describe "mirror_url/1" do
    test "appends /mirror" do
      assert Blossom.mirror_url("https://cdn.example") == "https://cdn.example/mirror"
      assert Blossom.mirror_url("https://cdn.example/") == "https://cdn.example/mirror"
      assert Blossom.mirror_url("https://cdn.example/upload") == "https://cdn.example/mirror"
      assert Blossom.mirror_url("https://cdn.example/mirror") == "https://cdn.example/mirror"
    end
  end

  describe "upload_data/3 large-blob mirroring" do
    @large_blob :crypto.strong_rand_bytes(5_000_000)
    @small_blob :crypto.strong_rand_bytes(1024)

    setup do
      agent = start_supervised!({Agent, fn -> %{mode: :mirror_ok, requests: []} end})

      bandit =
        start_supervised!(
          {Bandit, plug: {__MODULE__.MirrorStub, agent}, port: 0, ip: {127, 0, 0, 1}}
        )

      {:ok, {_ip, port}} = ThousandIsland.listener_info(bandit)
      %{agent: agent, server: "http://127.0.0.1:#{port}"}
    end

    test "mirrors blobs at or above 5MB instead of PUTting the body", %{
      agent: agent,
      server: server
    } do
      assert {:ok, result} =
               Blossom.upload_data(@large_blob, "episode.mp3",
                 private_key: :crypto.strong_rand_bytes(32),
                 server: server,
                 content_type: "audio/mpeg",
                 source_url: "https://www.corbettreport.com/mp3/flnwo02-hq.mp3"
               )

      assert result.url == "https://cdn.example/mirrored.mp3"
      assert requests(agent) == [{"PUT", "/mirror"}]
    end

    test "PUTs small blobs even when a source URL is present", %{agent: agent, server: server} do
      assert {:ok, _} =
               Blossom.upload_data(@small_blob, "photo.jpg",
                 private_key: :crypto.strong_rand_bytes(32),
                 server: server,
                 content_type: "image/jpeg",
                 source_url: "https://example.com/photo.jpg"
               )

      assert requests(agent) == [{"PUT", "/upload"}]
    end

    test "falls back to PUT /upload only when /mirror is missing", %{agent: agent, server: server} do
      Agent.update(agent, &Map.put(&1, :mode, :mirror_missing))

      assert {:ok, _} =
               Blossom.upload_data(@large_blob, "episode.mp3",
                 private_key: :crypto.strong_rand_bytes(32),
                 server: server,
                 content_type: "audio/mpeg",
                 source_url: "https://www.corbettreport.com/mp3/flnwo02-hq.mp3"
               )

      assert requests(agent) == [{"PUT", "/mirror"}, {"PUT", "/upload"}]
    end

    test "does not retry a 75MB PUT when /mirror fails for another reason", %{
      agent: agent,
      server: server
    } do
      Agent.update(agent, &Map.put(&1, :mode, :mirror_rejected))

      assert {:error, {:upload_failed, 403, _}} =
               Blossom.upload_data(@large_blob, "episode.mp3",
                 private_key: :crypto.strong_rand_bytes(32),
                 server: server,
                 content_type: "audio/mpeg",
                 source_url: "https://www.corbettreport.com/mp3/flnwo02-hq.mp3"
               )

      assert requests(agent) == [{"PUT", "/mirror"}]
    end

    defp requests(agent), do: Agent.get(agent, & &1.requests)
  end

  defmodule MirrorStub do
    @moduledoc false
    @behaviour Plug

    def init(agent), do: agent

    def call(conn, agent) do
      {:ok, _body, conn} = Plug.Conn.read_body(conn)
      mode = Agent.get(agent, & &1.mode)

      Agent.update(agent, fn state ->
        %{state | requests: state.requests ++ [{conn.method, conn.request_path}]}
      end)

      {status, body} =
        case {conn.method, conn.request_path, mode} do
          {"PUT", "/mirror", :mirror_ok} ->
            {201, descriptor(conn)}

          {"PUT", "/mirror", :mirror_missing} ->
            {404, "not found"}

          {"PUT", "/mirror", :mirror_rejected} ->
            {403, "ssrf denied"}

          {"PUT", "/upload", _} ->
            {201, descriptor(conn)}

          _ ->
            {404, "no"}
        end

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(status, body)
    end

    defp descriptor(_conn) do
      Jason.encode!(%{
        "url" => "https://cdn.example/mirrored.mp3",
        "sha256" => "aa",
        "size" => 1,
        "type" => "audio/mpeg"
      })
    end
  end

  describe "authorization_header/1" do
    test "uses Nostr scheme and standard Base64" do
      event = %{
        id: "7a1735c3852cf3f374edae4b2af2ee18e750e6dec583e19c4795d3b179af6d17",
        pubkey: "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798",
        created_at: 1_772_019_044,
        kind: 24_242,
        tags: [
          ["t", "upload"],
          ["expiration", "1708858680"],
          ["x", "b1674191a88ec5cdd733e4240a81803105dc412d6c6708d53ab94fc248f4f553"]
        ],
        content: "Upload Blob",
        sig: "deadbeef"
      }

      header = Blossom.authorization_header(event)
      assert String.starts_with?(header, "Nostr ")

      encoded = String.replace_prefix(header, "Nostr ", "")
      json = Base.decode64!(encoded)
      decoded = Jason.decode!(json)

      assert decoded["kind"] == 24_242
      assert decoded["content"] == "Upload Blob"
      assert ["t", "upload"] in decoded["tags"]
    end
  end

  describe "parse_descriptor/1" do
    test "parses a BUD-02 blob descriptor" do
      json = """
      {
        "url": "https://cdn.example.com/b1674191a88ec5cdd733e4240a81803105dc412d6c6708d53ab94fc248f4f553.png",
        "sha256": "b1674191a88ec5cdd733e4240a81803105dc412d6c6708d53ab94fc248f4f553",
        "size": 184292,
        "type": "image/png",
        "uploaded": 1725105921
      }
      """

      assert {:ok, result} = Blossom.parse_descriptor(json)
      assert result.url =~ "cdn.example.com"
      assert result.sha256 == "b1674191a88ec5cdd733e4240a81803105dc412d6c6708d53ab94fc248f4f553"
      assert result.size == 184_292
      assert result.type == "image/png"
    end

    test "rejects a payload without url" do
      assert {:error, :unexpected_response} = Blossom.parse_descriptor(%{"sha256" => "abc"})
    end

    test "rewrites audio/mpeg .mpga to .mp3" do
      json = """
      {
        "url": "https://route96.example/0eb42dad883310df7bdea79b0e07a722c249740ce5d91e7cd09ec1bf29ee283d.mpga",
        "sha256": "0eb42dad883310df7bdea79b0e07a722c249740ce5d91e7cd09ec1bf29ee283d",
        "size": 49612024,
        "type": "audio/mpeg",
        "nip94": [
          ["url", "https://route96.example/0eb42dad883310df7bdea79b0e07a722c249740ce5d91e7cd09ec1bf29ee283d.mpga"],
          ["m", "audio/mpeg"]
        ]
      }
      """

      assert {:ok, result} = Blossom.parse_descriptor(json)

      assert result.url ==
               "https://route96.example/0eb42dad883310df7bdea79b0e07a722c249740ce5d91e7cd09ec1bf29ee283d.mp3"

      assert result.nip94 == [
               [
                 "url",
                 "https://route96.example/0eb42dad883310df7bdea79b0e07a722c249740ce5d91e7cd09ec1bf29ee283d.mp3"
               ],
               ["m", "audio/mpeg"]
             ]
    end

    test "keeps a BUD-08 nip94 array" do
      json = """
      {
        "url": "https://route96.example/abc.png",
        "sha256": "aa",
        "size": 70,
        "type": "image/png",
        "uploaded": 1,
        "nip94": [["url", "https://route96.example/abc.png"], ["x", "aa"], ["m", "image/png"], ["dim", "1x1"]]
      }
      """

      assert {:ok, result} = Blossom.parse_descriptor(json)

      assert result.nip94 == [
               ["url", "https://route96.example/abc.png"],
               ["x", "aa"],
               ["m", "image/png"],
               ["dim", "1x1"]
             ]
    end
  end

  describe "already_hosted?/1" do
    test "recognizes only the configured Blossom host" do
      put_upload_endpoint("https://route96.example")

      assert Blossom.already_hosted?("https://route96.example/abc123.png")
      refute Blossom.already_hosted?("https://cdn.nostrcheck.me/photo.jpg")
      refute Blossom.already_hosted?("https://blossom.primal.net/photo.jpg")
    end

    test "is false when no endpoint is configured" do
      put_upload_endpoint(nil)
      refute Blossom.already_hosted?("https://route96.example/abc123.png")
    end
  end

  describe "ensure_post_image/2" do
    test "records an upload failure without marking the post processed" do
      put_upload_endpoint("https://route96.example")

      {:ok, source} =
        Sources.create_source(%{
          name: "Blossom Source",
          url: "https://example.com/blossom-#{System.unique_integer([:positive])}.xml",
          type: "rss",
          language: "en",
          active: true
        })

      url = "https://example.com/article-#{System.unique_integer([:positive])}"

      {:ok, post} =
        Posts.create_post(%{
          title: "Needs image",
          source_url: url,
          source_url_hash: Post.generate_url_hash(url),
          source_html: "<p>Content</p>",
          image: "https://127.0.0.1:1/missing.jpg",
          status: Post.status_pending_images(),
          source_id: source.id
        })

      private_key = :crypto.strong_rand_bytes(32)

      assert {:error, _} = Blossom.ensure_post_image(post, private_key)

      reloaded = Posts.get_post(post.id)
      refute reloaded.status == Post.status_processed()
      assert is_binary(reloaded.last_error)
      assert reloaded.last_error =~ "Blossom upload failed"
    end

    test "treats images already on the Blossom host as uploaded" do
      put_upload_endpoint("https://route96.example")

      {:ok, source} =
        Sources.create_source(%{
          name: "Hosted Image Source",
          url: "https://example.com/hosted-#{System.unique_integer([:positive])}.xml",
          type: "rss",
          language: "en",
          active: true
        })

      url = "https://example.com/article-#{System.unique_integer([:positive])}"
      image = "https://route96.example/hero.jpg"

      {:ok, post} =
        Posts.create_post(%{
          title: "Already hosted",
          source_url: url,
          source_url_hash: Post.generate_url_hash(url),
          source_html: ~s(<p><img src="#{image}" alt="Hero"></p><p>Body</p>),
          content: "![Hero](#{image})\n\nBody",
          image: image,
          status: Post.status_pending_images(),
          source_id: source.id
        })

      {:ok, _} = Posts.create_image(%{post_id: post.id, original_url: image})

      {stamped, _mapping} = Blossom.stamp_hosted_images(post)
      refute Blossom.pending_images?(stamped)

      images = Posts.list_images_for_post(post.id)
      assert Enum.all?(images, &(&1.uploaded_url == image))
    end

    test "does not treat a rewritten featured Blossom URL as still pending" do
      put_upload_endpoint("https://route96.example")

      {:ok, source} =
        Sources.create_source(%{
          name: "Rewritten Image Source",
          url: "https://example.com/rewritten-#{System.unique_integer([:positive])}.xml",
          type: "rss",
          language: "en",
          active: true
        })

      url = "https://example.com/article-#{System.unique_integer([:positive])}"
      original = "https://corbettreport.com/wp-content/uploads/hero.jpg"

      uploaded =
        "https://cdn.pareto.space/aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899.jpg"

      {:ok, post} =
        Posts.create_post(%{
          title: "Rewritten featured image",
          source_url: url,
          source_url_hash: Post.generate_url_hash(url),
          source_html: ~s(<p><img src="#{original}" alt="Hero"></p><p>Body</p>),
          content: "![Hero](#{uploaded})\n\nBody",
          image: uploaded,
          status: Post.status_pending_images(),
          last_error: "Images still need uploading",
          source_id: source.id
        })

      {:ok, _} =
        Posts.create_image(%{
          post_id: post.id,
          original_url: original,
          uploaded_url: uploaded
        })

      post = Posts.get_post(post.id, preload: [:images, :source])
      refute Blossom.pending_images?(post)

      assert {:ok, updated} = Rss2Nostr.Processing.Processor.ensure_images(post)
      assert updated.status == Post.status_processed()
      assert is_nil(updated.last_error)
    end

    test "reuses an uploaded CDN copy for the unwrapped S3 URL" do
      put_upload_endpoint("https://route96.example")

      {:ok, source} =
        Sources.create_source(%{
          name: "CDN Fallback Source",
          url: "https://example.com/cdn-#{System.unique_integer([:positive])}.xml",
          type: "rss",
          language: "en",
          active: true
        })

      url = "https://example.com/article-#{System.unique_integer([:positive])}"

      cdn =
        "https://substackcdn.com/image/fetch/w_56,c_limit,f_auto/https%3A%2F%2Fbucketeer-e05bbc84-baa3-437e-9518-adb32be77984.s3.amazonaws.com%2Fpublic%2Fimages%2Fa8e73950-03bb-4589-afaf-d9cdd55ab61b_500x500.png"

      origin =
        "https://bucketeer-e05bbc84-baa3-437e-9518-adb32be77984.s3.amazonaws.com/public/images/a8e73950-03bb-4589-afaf-d9cdd55ab61b_500x500.png"

      uploaded = "https://route96.example/card.png"

      {:ok, post} =
        Posts.create_post(%{
          title: "CDN sibling",
          source_url: url,
          source_url_hash: Post.generate_url_hash(url),
          content: "![Card](#{origin})",
          status: Post.status_pending_images(),
          source_id: source.id
        })

      {:ok, _} =
        Posts.create_image(%{
          post_id: post.id,
          original_url: cdn,
          uploaded_url: uploaded
        })

      {:ok, _} = Posts.create_image(%{post_id: post.id, original_url: origin})

      {stamped, _mapping} = Blossom.stamp_hosted_images(post)
      refute Blossom.pending_images?(stamped)

      images = Posts.list_images_for_post(post.id)
      assert Enum.all?(images, &(&1.uploaded_url == uploaded))
    end

    test "keeps the original video URL when the source does not mirror" do
      put_upload_endpoint("https://route96.example")

      {:ok, source} =
        Sources.create_source(%{
          name: "Original Video Source",
          url: "https://example.com/video-#{System.unique_integer([:positive])}.xml",
          type: "rss",
          language: "en",
          publish_as: "video",
          signing_nsec: "0000000000000000000000000000000000000000000000000000000000000001",
          options: %{"mirror_media" => "original"}
        })

      url = "http://127.0.0.1:1/nwnw640.mp4"

      {:ok, post} =
        Posts.create_post(%{
          title: "NWNW",
          source_url: url,
          source_url_hash: Post.generate_url_hash(url),
          content: "[Video](#{url} \"23:43 66928694\")\n\nThis week on NWNW.",
          status: Post.status_pending_images(),
          type: 34235,
          source_id: source.id
        })

      {:ok, post, 1} = Rss2Nostr.Processing.ImageExtractor.extract_and_store(post)
      {stamped, _mapping} = Blossom.stamp_hosted_images(post)

      refute Blossom.pending_images?(stamped)
      images = Posts.list_images_for_post(post.id)
      assert Enum.all?(images, &(&1.uploaded_url == url))
      imeta = hd(images).imeta
      assert "url #{url}" in imeta
      assert "m video/mp4" in imeta
      assert "duration 1423" in imeta
      assert "size 66928694" in imeta
    end

    test "rewrites a markdown audio link after a hosted stamp" do
      put_upload_endpoint("https://route96.example")

      {:ok, source} =
        Sources.create_source(%{
          name: "Hosted Audio Source",
          url: "https://example.com/audio-#{System.unique_integer([:positive])}.xml",
          type: "rss",
          language: "en",
          active: true
        })

      url = "https://example.com/article-#{System.unique_integer([:positive])}"
      audio = "https://route96.example/episode.mp3"

      {:ok, post} =
        Posts.create_post(%{
          title: "Already hosted audio",
          source_url: url,
          source_url_hash: Post.generate_url_hash(url),
          content: "[Audio](#{audio} \"45:12 49600123\")\n\nBody",
          status: Post.status_pending_images(),
          source_id: source.id
        })

      {:ok, post, 1} = Rss2Nostr.Processing.ImageExtractor.extract_and_store(post)
      {stamped, _mapping} = Blossom.stamp_hosted_images(post)

      refute Blossom.pending_images?(stamped)
      assert stamped.content =~ audio

      images = Posts.list_images_for_post(post.id)
      assert Enum.all?(images, &(&1.uploaded_url == audio))
      imeta = hd(images).imeta
      assert "url #{audio}" in imeta
      assert "m audio/mpeg" in imeta
      assert "duration 2712" in imeta
      assert "size 49600123" in imeta
    end

    test "skips posts without an image" do
      {:ok, source} =
        Sources.create_source(%{
          name: "No Image Source",
          url: "https://example.com/noimg-#{System.unique_integer([:positive])}.xml",
          type: "rss",
          language: "en",
          active: true
        })

      url = "https://example.com/article-#{System.unique_integer([:positive])}"

      {:ok, post} =
        Posts.create_post(%{
          title: "No image",
          source_url: url,
          source_url_hash: Post.generate_url_hash(url),
          source_html: "<p>Content</p>",
          status: Post.status_processed(),
          source_id: source.id
        })

      assert {:ok, updated} = Blossom.ensure_post_image(post, :crypto.strong_rand_bytes(32))
      assert updated.id == post.id
      assert updated.image in [nil, ""]
    end
  end
end
