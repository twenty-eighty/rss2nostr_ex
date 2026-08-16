defmodule Rss2Nostr.Processing.FootnotesTest do
  use ExUnit.Case, async: true

  alias Rss2Nostr.Processing.Footnotes

  test "extracts definitions after the article body" do
    content = """
    investor.[^43] later.[^44]

    ---

    [^43]: Merz made similar arrangements.

    [^44]: Ford, Matt: Russia Is Crashing Ukraine’s Hopes
    """

    {body, footnotes} = Footnotes.extract(content)

    assert body == "investor.[^43] later.[^44]"

    assert footnotes == [
             {"43", "[^43]: Merz made similar arrangements."},
             {"44", "[^44]: Ford, Matt: Russia Is Crashing Ukraine’s Hopes"}
           ]
  end

  test "keeps a multi-paragraph footnote together" do
    content = """
    See Kelly.[^2]

    [^2]: First line.

    Second line of the same note.

    [^3]: Next note.
    """

    {_body, footnotes} = Footnotes.extract(content)

    assert {"2", block} = List.keyfind(footnotes, "2", 0)
    assert block =~ "First line."
    assert block =~ "Second line of the same note."
    refute block =~ "Next note."
  end

  test "does not treat a definition inside a fence as the footnote section" do
    content = """
    Intro

    ```
    [^1]: not a footnote
    ```

    Body[^1]

    [^1]: Real note.
    """

    {body, footnotes} = Footnotes.extract(content)

    assert body =~ "```"
    assert body =~ "[^1]: not a footnote"
    assert footnotes == [{"1", "[^1]: Real note."}]
  end

  test "attaches only the notes a chunk cites" do
    footnotes = [
      {"1", "[^1]: First note."},
      {"2", "[^2]: Second note."}
    ]

    attached = Footnotes.attach("Hello[^1]", footnotes)

    assert attached =~ "[^1]: First note."
    refute attached =~ "[^2]: Second note."
  end

  test "last part also keeps notes that nobody cited" do
    footnotes = [
      {"1", "[^1]: First note."},
      {"2", "[^2]: Unused note."}
    ]

    attached = Footnotes.attach("Hello[^1]", footnotes, last: true, already_cited: [])

    assert attached =~ "[^1]: First note."
    assert attached =~ "[^2]: Unused note."
  end
end
