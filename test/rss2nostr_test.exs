defmodule Rss2NostrTest do
  use ExUnit.Case, async: true

  alias Rss2Nostr.Posts.Post

  describe "Posts" do
    test "generate_url_hash creates consistent MD5 hash" do
      url = "https://example.com/article/123"
      hash1 = Post.generate_url_hash(url)
      hash2 = Post.generate_url_hash(url)

      assert hash1 == hash2
      assert String.length(hash1) == 32
      assert Regex.match?(~r/^[a-f0-9]+$/, hash1)
    end

    test "generate_url_hash returns nil for non-binary" do
      assert Post.generate_url_hash(nil) == nil
      assert Post.generate_url_hash(123) == nil
    end
  end

  describe "Post status" do
    test "status constants are defined" do
      assert Post.status_new() == 0
      assert Post.status_processing() == 1
      assert Post.status_processed() == 2
      assert Post.status_published() == 6
      assert Post.status_error() == 8
      assert Post.status_pending_images() == 9
    end

    test "status_name returns correct names" do
      assert Post.status_name(0) == "new"
      assert Post.status_name(2) == "staging"
      assert Post.status_label(2) == "staging"
      assert Post.status_name(6) == "published"
      assert Post.status_name(9) == "pending_images"
      assert Post.status_label(9) == "pending images"
      assert Post.status_name(999) == "unknown"
    end
  end
end
