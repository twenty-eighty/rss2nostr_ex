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
    assert html =~ "<li>one</li>"
    assert html =~ "<li>two</li>"
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
end
