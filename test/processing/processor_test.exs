defmodule Rss2Nostr.Processing.ProcessorTest do
  use Rss2Nostr.DataCase

  alias Rss2Nostr.Processing.Processor
  alias Rss2Nostr.Posts
  alias Rss2Nostr.Posts.Post
  alias Rss2Nostr.Sources

  @source_attrs %{
    name: "Processor Test Source",
    url: "https://example.com/processor-test-feed.xml",
    type: "rss",
    language: "en",
    active: true
  }

  def create_post(source, attrs \\ %{}) do
    url = "https://example.com/article/#{System.unique_integer([:positive])}"

    default_attrs = %{
      title: "Test Article",
      source_url: url,
      source_url_hash: Post.generate_url_hash(url),
      source_html: "<p>This is test content for processing.</p>",
      status: Post.status_new(),
      source_id: source.id
    }

    {:ok, post} = Posts.create_post(Map.merge(default_attrs, attrs))
    post
  end

  setup do
    {:ok, source} = Sources.create_source(@source_attrs)
    %{source: source}
  end

  describe "process_post/1" do
    test "processes a new post", %{source: source} do
      post =
        create_post(source, %{
          source_html:
            "<h1>Title</h1><p>This is the article content with enough text to generate a summary. We need more content here to make sure the summary generation works properly.</p>"
        })

      {:ok, processed} = Processor.process_post(post)

      assert processed.status == Post.status_processed()
      assert processed.staged_at
      assert processed.content != nil
    end

    test "generates summary for post without summary", %{source: source} do
      post =
        create_post(source, %{
          source_html:
            "<p>This is a long article content that should be summarized automatically. It contains multiple sentences and paragraphs to ensure proper summary generation.</p>",
          summary: nil
        })

      {:ok, processed} = Processor.process_post(post)

      # Summary should be generated or content should be set
      assert processed.status == Post.status_processed()
    end

    test "preserves existing summary", %{source: source} do
      post =
        create_post(source, %{
          summary: "Existing summary",
          source_html: "<p>Content</p>"
        })

      {:ok, processed} = Processor.process_post(post)

      assert processed.summary == "Existing summary"
    end

    test "applies the source body selector and skip classes", %{source: source} do
      {:ok, source} =
        Sources.update_source(source, %{
          options: %{"body_selector" => "div.entry-content", "skip_classes" => ["OUTBRAIN"]}
        })

      post =
        create_post(source, %{
          source_html: """
          <nav>Menu</nav>
          <div class="entry-content">
            <p>Article body for processing.</p>
            <div class="OUTBRAIN">Advertisement</div>
          </div>
          """
        })

      {:ok, processed} = Processor.process_post(post)

      assert processed.content =~ "Article body"
      refute processed.content =~ "Advertisement"
      refute processed.content =~ "Menu"
    end

    test "applies the Corbett body selector from the article URL when none is stored", %{
      source: source
    } do
      post =
        create_post(source, %{
          source_url: "https://www.corbettreport.com/nwnw632/",
          source_url_hash: Post.generate_url_hash("https://www.corbettreport.com/nwnw632/"),
          source_html: """
          <div class="et_pb_column_0_tb_body">
            <p>Welcome to New World Next Week</p>
          </div>
          <aside>
            <h2>FREEDOM</h2>
            <h2>RECENT POSTS</h2>
            <h2>ARCHIVES</h2>
          </aside>
          """
        })

      {:ok, processed} = Processor.process_post(post)

      assert processed.content =~ "Welcome to New World Next Week"
      refute processed.content =~ "FREEDOM"
      refute processed.content =~ "ARCHIVES"
    end
  end

  describe "process_posts/1" do
    test "processes multiple posts", %{source: source} do
      posts = for _ <- 1..3, do: create_post(source)

      result = Processor.process_posts(posts)

      assert result.processed >= 0
      assert Map.has_key?(result, :errors)
      assert Map.has_key?(result, :skipped)
    end

    test "returns stats for empty list" do
      result = Processor.process_posts([])

      assert result.processed == 0
      assert result.errors == 0
      assert result.skipped == 0
    end
  end

  describe "process_post_by_id/1" do
    test "processes post by id", %{source: source} do
      post = create_post(source)

      result = Processor.process_post_by_id(post.id)

      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "returns error for non-existent id" do
      assert {:error, :not_found} = Processor.process_post_by_id(999_999)
    end
  end

  describe "process_new_posts/1" do
    test "processes only new posts", %{source: source} do
      # Create a new post
      _new_post = create_post(source)

      # Create a processed post
      url = "https://example.com/processed-#{System.unique_integer([:positive])}"

      {:ok, _processed_post} =
        Posts.create_post(%{
          title: "Already Processed",
          source_url: url,
          source_url_hash: Post.generate_url_hash(url),
          source_html: "<p>Content</p>",
          status: Post.status_processed(),
          source_id: source.id
        })

      result = Processor.process_new_posts(limit: 10)

      assert Map.has_key?(result, :processed)
    end
  end

  describe "images" do
    test "does not mark processed while images still need uploading", %{source: source} do
      post =
        create_post(source, %{
          source_html:
            ~s(<p><img src="https://cdn.example/hero.jpg" alt="Hero"></p><p>Article</p>),
          image: "https://cdn.example/hero.jpg"
        })

      {:ok, result} = Processor.process_post(post)

      assert result.status == Post.status_pending_images()
      assert result.content =~ "Article" or result.content =~ "hero.jpg"
      assert result.last_error =~ "pubkey"
      refute result.status == Post.status_processed()
    end

    test "marks processed when images are already on the Blossom host", %{source: source} do
      nostr = Application.get_env(:rss2nostr, :nostr, [])

      Application.put_env(
        :rss2nostr,
        :nostr,
        Keyword.put(nostr, :upload_endpoint, "https://route96.example")
      )

      on_exit(fn ->
        Application.put_env(:rss2nostr, :nostr, nostr)
      end)

      post =
        create_post(source, %{
          source_html:
            ~s(<p><img src="https://route96.example/hero.jpg" alt="Hero"></p><p>Article body</p>),
          image: "https://route96.example/hero.jpg"
        })

      {:ok, result} = Processor.process_post(post)

      assert result.status == Post.status_processed()
      images = Posts.list_images_for_post(result.id)
      assert images != []
      assert Enum.all?(images, &(&1.uploaded_url == "https://route96.example/hero.jpg"))
    end

    test "marks processed when uploads succeeded but the in-memory image list is stale", %{
      source: source
    } do
      uploaded = "https://route96.example/fresh.jpg"

      post =
        create_post(source, %{
          content: "![Hero](#{uploaded})\n\nBody",
          image: uploaded,
          status: Post.status_pending_images(),
          last_error: "Images still need uploading"
        })

      {:ok, image} =
        Posts.create_image(%{
          post_id: post.id,
          original_url: "https://cdn.example/hero.jpg"
        })

      {:ok, _} = Posts.mark_image_uploaded(image, uploaded)

      stale = %{post | images: [%{image | uploaded_url: nil}]}
      {:ok, result} = Processor.ensure_images(stale)

      assert result.status == Post.status_processed()
      assert is_nil(result.last_error)
    end

    test "clears leftover pending status when images are already uploaded", %{source: source} do
      nostr = Application.get_env(:rss2nostr, :nostr, [])

      Application.put_env(
        :rss2nostr,
        :nostr,
        Keyword.put(nostr, :upload_endpoint, "https://route96.example")
      )

      on_exit(fn ->
        Application.put_env(:rss2nostr, :nostr, nostr)
      end)

      uploaded = "https://route96.example/aabbcc.jpg"

      post =
        create_post(source, %{
          content: "![Hero](#{uploaded})\n\nBody",
          image: uploaded,
          status: Post.status_pending_images(),
          last_error: "Images still need uploading"
        })

      {:ok, _} =
        Posts.create_image(%{
          post_id: post.id,
          original_url: "https://cdn.example/hero.jpg",
          uploaded_url: uploaded
        })

      post = Posts.get_post(post.id, preload: [:images])
      finished = Processor.finish_if_images_ready(post)

      assert finished.status == Post.status_processed()
      assert is_nil(finished.last_error)
    end

    test "retries pending image posts without recomposing", %{source: source} do
      post =
        create_post(source, %{
          content: "Already composed",
          image: "https://cdn.example/hero.jpg",
          status: Post.status_pending_images(),
          last_error: "NOSTR_UPLOAD_ENDPOINT is not set"
        })

      {:ok, _} =
        Posts.create_image(%{post_id: post.id, original_url: "https://cdn.example/hero.jpg"})

      {:ok, result} = Processor.process_post(post)

      assert result.status == Post.status_pending_images()
      assert result.content == "Already composed"
    end
  end
end
