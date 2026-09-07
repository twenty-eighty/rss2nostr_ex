defmodule Rss2Nostr.Import.FeedFetcherTest do
  use ExUnit.Case, async: true

  alias Rss2Nostr.Import.FeedFetcher

  describe "fetch/1" do
    test "returns error for invalid URL input" do
      assert {:error, "Invalid URL"} = FeedFetcher.fetch(nil)
      assert {:error, "Invalid URL"} = FeedFetcher.fetch(123)
      assert {:error, "Invalid URL"} = FeedFetcher.fetch([])
    end

    test "returns error for non-existent domain" do
      {:error, reason} =
        FeedFetcher.fetch("https://this-domain-does-not-exist-12345.invalid/feed.xml")

      assert is_binary(reason)
      assert reason =~ "Request failed" or reason =~ "HTTP"
      refute reason =~ "FunctionClauseError"
    end

    test "formats atom HTTP errors without crashing" do
      previous = Application.get_env(:rss2nostr, :http_ssrf_protection)

      try do
        Application.put_env(:rss2nostr, :http_ssrf_protection, true)

        assert {:error, reason} = FeedFetcher.fetch("http://127.0.0.1/feed.xml")
        assert reason == "Request failed: blocked_address"
      after
        Application.put_env(:rss2nostr, :http_ssrf_protection, previous)
      end
    end

    test "returns error for invalid URL format" do
      # This should fail during HTTP request
      result = FeedFetcher.fetch("not-a-valid-url")

      assert match?({:error, _}, result)
    end
  end

  describe "fetch_article/1" do
    test "returns error for invalid URL input" do
      assert {:error, "Invalid URL"} = FeedFetcher.fetch_article(nil)
      assert {:error, "Invalid URL"} = FeedFetcher.fetch_article(123)
      assert {:error, "Invalid URL"} = FeedFetcher.fetch_article(%{})
    end

    test "returns error for non-existent domain" do
      {:error, reason} =
        FeedFetcher.fetch_article("https://nonexistent-domain-xyz.invalid/article")

      assert is_binary(reason)
    end
  end
end
