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
