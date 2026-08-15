defmodule Rss2Nostr.Processing.ArticleSplitTest do
  use ExUnit.Case, async: true

  alias Rss2Nostr.Nostr.Event
  alias Rss2Nostr.Processing.ArticleSplit

  defp size_plus_overhead(chunk, _index), do: byte_size(chunk) + 200

  test "keeps a short article as one part" do
    assert ArticleSplit.split("## Hello\n\nBody", &size_plus_overhead/2, max_size: 1000) ==
             ["## Hello\n\nBody"]
  end

  test "prefers a heading near the size limit" do
    first = "## Intro\n\n" <> String.duplicate("a", 400)
    second = "## Next\n\n" <> String.duplicate("b", 400)
    content = first <> "\n\n" <> second

    [part1, part2] = ArticleSplit.split(content, &size_plus_overhead/2, max_size: 700)

    assert part1 =~ "## Intro"
    refute part1 =~ "## Next"
    assert String.starts_with?(String.trim_leading(part2), "## Next")
  end

  test "falls back to a blank line when no heading is nearby" do
    para = String.duplicate("word ", 80)
    content = para <> "\n\n" <> para <> "\n\n" <> para

    parts = ArticleSplit.split(content, &size_plus_overhead/2, max_size: 500)

    assert length(parts) >= 2
    assert Enum.all?(parts, &(byte_size(&1) + 200 <= 500 or String.length(&1) < 20))
  end

  test "does not split on a heading inside a fenced code block" do
    fence = """
    ```
    ## Not a heading
    #{String.duplicate("c", 400)}
    ```
    """

    after_fence = "\n\n## Real\n\n" <> String.duplicate("d", 200)
    content = fence <> after_fence

    parts = ArticleSplit.split(content, &size_plus_overhead/2, max_size: 500)

    assert Enum.any?(parts, &String.contains?(&1, "## Not a heading"))
    assert Enum.any?(parts, &String.contains?(&1, "## Real"))
    refute Enum.any?(parts, &String.starts_with?(String.trim_leading(&1), "## Not a heading"))
  end

  test "measured NIP-44 plaintext of each part stays in range" do
    pubkey = String.duplicate("0", 64)
    body = String.duplicate("lorem ipsum dolor sit amet. ", 2500)

    content =
      Enum.map_join(1..6, "\n\n", fn n ->
        "## Section #{n}\n\n#{body}"
      end)

    measure = fn chunk, index ->
      Event.build_long_form(pubkey, chunk,
        title: "Huge Article (#{index}/99)",
        summary: "A long summary for overhead",
        image: "https://example.com/hero.jpg",
        identifier: "huge-article-p99",
        author_pubkey: pubkey
      )
      |> Event.draft_plaintext_size()
    end

    parts = ArticleSplit.split(content, measure)
    max = Event.max_draft_plaintext_size()

    assert length(parts) > 1

    Enum.with_index(parts, 1)
    |> Enum.each(fn {part, index} ->
      assert measure.(part, index) <= max
    end)
  end
end
