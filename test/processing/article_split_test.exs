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

  test "splits into roughly equal parts instead of packing the first to the limit" do
    content =
      Enum.map_join(1..3, "\n\n", fn n ->
        "## S#{n}\n\n" <> String.duplicate(<<?a + n - 1>>, 400)
      end)

    parts = ArticleSplit.split(content, &size_plus_overhead/2, max_size: 900)
    sizes = Enum.map(parts, &byte_size/1)

    assert length(parts) == 3
    assert Enum.max(sizes) / Enum.min(sizes) <= 1.3
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

  test "puts footnotes cited in the first part on the first event" do
    first = "## Intro\n\n" <> String.duplicate("a", 400) <> "[^1]"
    second = "## Next\n\n" <> String.duplicate("b", 400) <> "[^2]"

    content =
      first <>
        "\n\n" <>
        second <>
        "\n\n---\n\n[^1]: First note about the intro.\n\n[^2]: Second note about the rest."

    [part1, part2] = ArticleSplit.split(content, &size_plus_overhead/2, max_size: 800)

    assert part1 =~ "## Intro"
    assert part1 =~ "[^1]"
    assert part1 =~ "[^1]: First note about the intro."
    refute part1 =~ "[^2]: Second note"
    assert part2 =~ "[^2]: Second note about the rest."
    refute part2 =~ "[^1]: First note"
  end

  test "keeps uncited leftover footnotes on the last part" do
    first = "## Intro\n\n" <> String.duplicate("a", 400) <> "[^1]"
    second = "## Next\n\n" <> String.duplicate("b", 400)

    content =
      first <> "\n\n" <> second <> "\n\n---\n\n[^1]: Cited in the intro.\n\n[^2]: Never cited."

    [part1, part2] = ArticleSplit.split(content, &size_plus_overhead/2, max_size: 800)

    assert part1 =~ "[^1]: Cited in the intro."
    refute part1 =~ "[^2]: Never cited."
    assert part2 =~ "[^2]: Never cited."
  end

  test "keeps footnotes on a short article that does not split" do
    content = "Hello[^1]\n\n---\n\n[^1]: A note."

    assert ArticleSplit.split(content, &size_plus_overhead/2, max_size: 1000) == [
             "Hello[^1]\n\n---\n\n[^1]: A note."
           ]
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
