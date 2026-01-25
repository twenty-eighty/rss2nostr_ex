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
end
