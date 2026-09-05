defmodule Rss2Nostr.Processing.Sites.WpFootnotesTest do
  use ExUnit.Case, async: true

  alias Rss2Nostr.Processing.{HtmlToMarkdown, Sites}

  defp convert(html, opts \\ []) do
    html
    |> Sites.preprocess(opts)
    |> HtmlToMarkdown.convert()
  end

  test "converts Footnotes Made Easy identifier and definition" do
    html = """
    <p>HSG.<sup><a href="#footnote_1_8346" id="identifier_1_8346"
      class="footnote-link footnote-identifier-link" title="tooltip">1</a></sup> Meckel</p>
    <ol class="footnotes">
      <li id="footnote_1_8346" class="footnote">
        <a href="https://example.com/a">https://example.com/a</a> and more.
        <span class="footnote-back-link-wrapper">[<a href="#identifier_1_8346"
          class="footnote-link footnote-back-link">↩</a>]</span>
      </li>
    </ol>
    """

    md = convert(html, url: "https://einfachkompliziert.de/mediale-hetze-miriam-meckel-replik/")

    assert md =~ "HSG.[^1]"
    assert md =~ "[^1]: [https://example.com/a](https://example.com/a) and more."
    refute md =~ "#footnote_1_8346"
    refute md =~ "↩"
    refute md =~ ~r/^1\. /m
  end

  test "converts several WordPress footnotes" do
    html = """
    <p>One.<a href="#footnote_1_10" class="footnote-identifier-link">1</a>
      Two.<a href="#footnote_2_10" class="footnote-identifier-link">2</a></p>
    <ol class="footnotes">
      <li id="footnote_1_10" class="footnote">First.<a href="#identifier_1_10" class="footnote-back-link">↩</a></li>
      <li id="footnote_2_10" class="footnote">Second.<a href="#identifier_2_10" class="footnote-back-link">↩</a></li>
    </ol>
    """

    md = convert(html)

    assert md =~ "One.[^1]"
    assert md =~ "Two.[^2]"
    assert md =~ "[^1]: First."
    assert md =~ "[^2]: Second."
    assert md =~ "[^1]: First.\n\n[^2]: Second."
  end
end
