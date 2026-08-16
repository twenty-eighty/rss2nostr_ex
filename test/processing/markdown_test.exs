defmodule Rss2Nostr.Processing.MarkdownTest do
  use ExUnit.Case, async: true

  alias Rss2Nostr.Processing.Markdown

  test "renders headings, emphasis, and links" do
    html = Markdown.to_html("# Title\n\nHello **world** and [here](https://example.com).")

    assert html =~ "<h1>Title</h1>"
    assert html =~ "<strong>world</strong>"
    assert html =~ ~s(<a href="https://example.com">here</a>)
  end

  test "renders images and lists" do
    html =
      Markdown.to_html("""
      ![Alt](https://example.com/pic.jpg)

      - one
      - two
      """)

    assert html =~ ~s(<img src="https://example.com/pic.jpg" alt="Alt">)
    refute html =~ "<figure>"
    assert html =~ "<li>one</li>"
    assert html =~ "<li>two</li>"
  end

  test "renders an image title as a visible caption" do
    html = Markdown.to_html("![](https://example.com/pic.jpg \"Ashot Grigorian\")")

    assert html =~ "<figure>"
    assert html =~ ~s(<img src="https://example.com/pic.jpg" alt="">)
    assert html =~ "<figcaption>Ashot Grigorian</figcaption>"
    refute html =~ "<p><figure>"
  end

  test "escapes raw HTML and drops javascript URLs" do
    html = Markdown.to_html("Click [x](javascript:alert(1)) and <script>alert(1)</script>")

    refute html =~ "<script>"
    refute html =~ "javascript:"
    assert html =~ "&lt;script&gt;"
  end

  test "renders fenced code without interpreting markup" do
    html = Markdown.to_html("```\n**not bold**\n```")

    assert html =~ "<pre><code>"
    assert html =~ "**not bold**"
    refute html =~ "<strong>"
  end

  test "renders Markdown footnotes as linked superscripts" do
    html =
      Markdown.to_html("""
      investor.[^43]

      [^43]: Merz made similar arrangements.
      """)

    assert html =~ ~s(<sup class="footnote-ref" id="fnref-43"><a href="#fn-43">43</a></sup>)
    assert html =~ ~s(<p class="footnote" id="fn-43"><a href="#fnref-43">43</a>.)
    assert html =~ "Merz made similar arrangements."
    refute html =~ "[^43]"
  end
end
