defmodule Rss2Nostr.Processing.ImageExtractorTest do
  use Rss2Nostr.DataCase

  alias Rss2Nostr.Processing.ImageExtractor
  alias Rss2Nostr.Posts
  alias Rss2Nostr.Posts.Post
  alias Rss2Nostr.Sources

  def create_test_post(source, html_content) do
    url = "https://example.com/article/#{System.unique_integer([:positive])}"

    {:ok, post} =
      Posts.create_post(%{
        title: "Image Test Article",
        source_url: url,
        source_url_hash: Post.generate_url_hash(url),
        source_html: html_content,
        status: Post.status_new(),
        source_id: source.id
      })

    post
  end

  setup do
    {:ok, source} =
      Sources.create_source(%{
        name: "Image Extractor Test Source",
        url: "https://example.com/image-test-feed.xml",
        type: "rss",
        language: "en",
        active: true
      })

    %{source: source}
  end

  describe "extract_images/2" do
    test "extracts images from HTML content" do
      html = """
      <article>
        <img src="https://example.com/image1.jpg" alt="Image 1">
        <p>Some text</p>
        <img src="https://example.com/image2.png" alt="Image 2">
      </article>
      """

      images = ImageExtractor.extract_images(html)

      assert is_list(images)
      # Images are returned as maps with :url, :alt, :caption fields
      urls = Enum.map(images, & &1.url)
      assert "https://example.com/image1.jpg" in urls or images == []
    end

    test "handles content without images" do
      html = "<p>Just text, no images here.</p>"

      images = ImageExtractor.extract_images(html)

      assert is_list(images)
    end

    test "handles nil content" do
      images = ImageExtractor.extract_images(nil)

      assert images == []
    end

    test "includes featured image when provided" do
      html = "<p>Content</p>"
      featured = "https://example.com/featured.jpg"

      images = ImageExtractor.extract_images(html, featured)

      # Featured image should be included as a map
      urls = Enum.map(images, & &1.url)
      assert featured in urls
    end
  end

  describe "extract_and_store/1" do
    test "extracts and stores images for post", %{source: source} do
      html = """
      <article>
        <img src="https://example.com/stored-image.jpg" alt="Stored Image">
      </article>
      """

      post = create_test_post(source, html)

      result = ImageExtractor.extract_and_store(post)

      assert match?({:ok, %Post{}, _}, result)
    end

    test "repairs Cloudinary fetch fragments and stores the original URL", %{source: source} do
      fragment =
        "fl_progressive:steep/https%3A%2F%2Fpbs.substack.com%2Fprofile_images%2F1829651769380503552%2FbMTtwSuG.jpg"

      original =
        "https://pbs.substack.com/profile_images/1829651769380503552/bMTtwSuG.jpg"

      post = create_test_post(source, "<p>x</p>")

      {:ok, post} =
        Posts.update_post(post, %{
          content: "[![](#{fragment})Carmen Drescher](https://substack.com/@carmen)"
        })

      {:ok, post, count} = ImageExtractor.extract_and_store(post)

      assert count == 1
      assert post.content =~ original
      refute post.content =~ "fl_progressive:steep"

      urls = Enum.map(Posts.list_images_for_post(post.id), & &1.original_url)
      assert original in urls
    end

    test "does not create a new row for the unwrapped form of an uploaded CDN URL", %{
      source: source
    } do
      cdn =
        "https://substackcdn.com/image/fetch/w_56,c_limit,f_auto/https%3A%2F%2Fbucketeer-e05bbc84-baa3-437e-9518-adb32be77984.s3.amazonaws.com%2Fpublic%2Fimages%2Fa8e73950-03bb-4589-afaf-d9cdd55ab61b_500x500.png"

      origin =
        "https://bucketeer-e05bbc84-baa3-437e-9518-adb32be77984.s3.amazonaws.com/public/images/a8e73950-03bb-4589-afaf-d9cdd55ab61b_500x500.png"

      post = create_test_post(source, "<p>x</p>")
      {:ok, post} = Posts.update_post(post, %{content: "![Card](#{origin})"})

      {:ok, _} =
        Posts.create_image(%{
          post_id: post.id,
          original_url: cdn,
          uploaded_url: "https://route96.example/card.png"
        })

      {:ok, _post, created} = ImageExtractor.extract_and_store(post)

      assert created == 0
      assert length(Posts.list_images_for_post(post.id)) == 1
    end

    test "does not create a new row for a URL that was already uploaded", %{source: source} do
      original = "https://cdn.example/hero.jpg"
      uploaded = "https://route96.example/hero.jpg"
      post = create_test_post(source, "<p>x</p>")

      {:ok, post} = Posts.update_post(post, %{content: "![Hero](#{uploaded})", image: uploaded})

      {:ok, _} =
        Posts.create_image(%{
          post_id: post.id,
          original_url: original,
          uploaded_url: uploaded
        })

      {:ok, _post, created} = ImageExtractor.extract_and_store(post)

      assert created == 0
      assert length(Posts.list_images_for_post(post.id)) == 1
    end

    test "drops VG Wort tracking pixels from content and stored images", %{source: source} do
      pixel = "https://vg09.met.vgwort.de/na/ca9760d03d7f450dba63db90362e74e7"
      photo = "https://cdn.example/photo.jpg"
      post = create_test_post(source, "<p>x</p>")

      {:ok, post} =
        Posts.update_post(post, %{
          content: "![Photo](#{photo})\n\n![](#{pixel})",
          image: pixel
        })

      {:ok, _} = Posts.create_image(%{post_id: post.id, original_url: pixel})
      {:ok, _} = Posts.create_image(%{post_id: post.id, original_url: photo})

      {:ok, post, created} = ImageExtractor.extract_and_store(post)

      assert created == 0
      refute post.content =~ "vgwort"
      assert post.content =~ photo
      assert is_nil(post.image)

      urls = Enum.map(Posts.list_images_for_post(post.id), & &1.original_url)
      assert photo in urls
      refute Enum.any?(urls, &String.contains?(&1, "vgwort"))
    end
  end

  describe "extract_audio/1" do
    test "extracts markdown audio links and ignores pages and images" do
      markdown = """
      ![Cover](https://example.com/cover.jpg)

      [Audio](https://www.corbettreport.com/mp3/episode506_reading.mp3)

      [YouTube](https://www.youtube.com/watch?v=abc)

      [Interview](https://cdn.example/show.m4a?_=1)
      """

      urls = Enum.map(ImageExtractor.extract_audio(markdown), & &1.url)

      assert "https://www.corbettreport.com/mp3/episode506_reading.mp3" in urls
      assert "https://cdn.example/show.m4a?_=1" in urls
      refute "https://example.com/cover.jpg" in urls
      refute "https://www.youtube.com/watch?v=abc" in urls
    end

    test "returns empty list when there is no audio" do
      assert ImageExtractor.extract_audio("[Read](https://corbettreport.com/nwnw639/)") == []
    end
  end

  describe "extract_video/1" do
    test "extracts markdown video links and duration captions" do
      markdown = """
      [Video](https://www.corbettreport.com/mp4/nwnw640.mp4 "23:43")

      [YouTube](https://www.youtube.com/watch?v=abc)
      """

      [video] = ImageExtractor.extract_video(markdown)
      assert video.url == "https://www.corbettreport.com/mp4/nwnw640.mp4"
      assert video.caption == "23:43"
      assert ImageExtractor.clock_to_seconds(video.caption) == 1423
      assert ImageExtractor.parse_media_caption("23:43 66928694") == %{duration: 1423, size: 66_928_694}
    end
  end

  describe "extract_and_store/1 audio" do
    test "stores an audio file link from markdown", %{source: source} do
      post = create_test_post(source, "<p>x</p>")
      audio = "https://www.corbettreport.com/mp3/episode506_reading.mp3"

      {:ok, post} =
        Posts.update_post(post, %{content: "[Audio](#{audio})\n\nBody"})

      {:ok, _post, count} = ImageExtractor.extract_and_store(post)

      assert count == 1
      urls = Enum.map(Posts.list_images_for_post(post.id), & &1.original_url)
      assert audio in urls
    end

    test "does not create a second row after the audio URL was replaced", %{source: source} do
      original = "https://www.corbettreport.com/mp3/episode506_reading.mp3"
      uploaded = "https://route96.example/episode.mp3"
      post = create_test_post(source, "<p>x</p>")

      {:ok, post} = Posts.update_post(post, %{content: "[Audio](#{uploaded})"})

      {:ok, _} =
        Posts.create_image(%{
          post_id: post.id,
          original_url: original,
          uploaded_url: uploaded
        })

      {:ok, _post, created} = ImageExtractor.extract_and_store(post)

      assert created == 0
      assert length(Posts.list_images_for_post(post.id)) == 1
    end
  end

  describe "extract_markdown_images/1" do
    test "extracts images from markdown content" do
      markdown = """
      Some text here.

      ![Alt text](https://example.com/markdown-image.jpg)

      More text.

      ![Another](https://example.com/another.png)
      """

      images = ImageExtractor.extract_markdown_images(markdown)

      assert is_list(images)
      # Images are returned as maps
      urls = Enum.map(images, & &1.url)
      assert "https://example.com/markdown-image.jpg" in urls
      assert "https://example.com/another.png" in urls
    end

    test "returns empty list for content without images" do
      markdown = "Just text, no images"

      images = ImageExtractor.extract_markdown_images(markdown)

      assert images == []
    end

    test "handles nil content" do
      images = ImageExtractor.extract_markdown_images(nil)

      assert images == []
    end
  end

  describe "normalize_url/1" do
    test "unwraps an encoded Cloudinary fetch target" do
      url =
        "https://substackcdn.com/image/fetch/w_192,c_limit,f_auto,q_auto:good,fl_progressive:steep/https%3A%2F%2Fpbs.substack.com%2Fprofile_images%2F1829651769380503552%2FbMTtwSuG.jpg"

      assert ImageExtractor.normalize_url(url) ==
               "https://pbs.substack.com/profile_images/1829651769380503552/bMTtwSuG.jpg"
    end

    test "unwraps a leftover srcset fragment" do
      url =
        "fl_progressive:steep/https%3A%2F%2Fpbs.substack.com%2Fprofile_images%2F1829651769380503552%2FbMTtwSuG.jpg"

      assert ImageExtractor.normalize_url(url) ==
               "https://pbs.substack.com/profile_images/1829651769380503552/bMTtwSuG.jpg"
    end
  end

  describe "display_url/1" do
    test "rewraps a Substack HEIC origin for browsers" do
      origin =
        "https://substack-post-media.s3.amazonaws.com/public/images/47485710-5d05-4cea-a61c-53138cfa407b_4032x3024.heic"

      displayed = ImageExtractor.display_url(origin)

      assert String.starts_with?(displayed, "https://substackcdn.com/image/fetch/f_jpg/")
      assert displayed =~ "47485710-5d05-4cea-a61c-53138cfa407b_4032x3024.heic"
    end

    test "still unwraps a JPEG Substack CDN URL" do
      url =
        "https://substackcdn.com/image/fetch/w_192,c_limit,f_auto,q_auto:good,fl_progressive:steep/https%3A%2F%2Fpbs.substack.com%2Fprofile_images%2F1829651769380503552%2FbMTtwSuG.jpg"

      assert ImageExtractor.display_url(url) ==
               "https://pbs.substack.com/profile_images/1829651769380503552/bMTtwSuG.jpg"
    end
  end

  describe "download_urls/1" do
    test "adds a Substack CDN fetch URL after a blocked S3 origin" do
      origin =
        "https://bucketeer-e05bbc84-baa3-437e-9518-adb32be77984.s3.amazonaws.com/public/images/a8e73950-03bb-4589-afaf-d9cdd55ab61b_500x500.png"

      urls = ImageExtractor.download_urls(origin)

      assert hd(urls) == origin
      assert Enum.any?(urls, &String.starts_with?(&1, "https://substackcdn.com/image/fetch/"))
      assert Enum.any?(urls, &String.contains?(&1, "https%3A%2F%2Fbucketeer"))
    end

    test "does not wrap a URL that is already on the Substack CDN" do
      cdn =
        "https://substackcdn.com/image/fetch/w_56,c_limit,f_auto,q_auto:good,fl_progressive:steep/https%3A%2F%2Fbucketeer-e05bbc84-baa3-437e-9518-adb32be77984.s3.amazonaws.com%2Fpublic%2Fimages%2Fa8e73950-03bb-4589-afaf-d9cdd55ab61b_500x500.png"

      origin =
        "https://bucketeer-e05bbc84-baa3-437e-9518-adb32be77984.s3.amazonaws.com/public/images/a8e73950-03bb-4589-afaf-d9cdd55ab61b_500x500.png"

      urls = ImageExtractor.download_urls(cdn)
      assert hd(urls) == cdn
      assert origin in urls
      refute Enum.any?(urls, &String.contains?(&1, "substackcdn.com/image/fetch/%"))
    end
  end

  describe "replace_image_urls/2" do
    test "replaces image URLs in content" do
      content = "<img src=\"https://old.com/image.jpg\">"
      mapping = %{"https://old.com/image.jpg" => "https://new.com/image.jpg"}

      result = ImageExtractor.replace_image_urls(content, mapping)

      assert result =~ "https://new.com/image.jpg"
      refute result =~ "https://old.com/image.jpg"
    end

    test "handles empty mapping" do
      content = "<img src=\"https://example.com/image.jpg\">"

      result = ImageExtractor.replace_image_urls(content, %{})

      assert result == content
    end
  end
end
