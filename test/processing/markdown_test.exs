defmodule Rss2Nostr.Processing.MarkdownTest do
  use ExUnit.Case, async: true

  alias Rss2Nostr.Processing.Markdown

  test "renders a two-space hard break as br in one paragraph" do
    html =
      Markdown.to_html(
        "Story #3: US Man Accused Of Destroying Evidence By Wiping Phone At Airport  \nhttps://www.msn.com/en-us/news/other/us-man-accused-of-destroying-evidence-by-wiping-phone-at-airport/ar-AA28ZvnE"
      )

    assert html =~ "Airport<br>\nhttps://www.msn.com/"
    refute html =~ "</p>\n<p>"
    refute html =~ "\\"
  end

  test "renders a backslash hard break as br" do
    html =
      Markdown.to_html(
        "Video: 404 Media – Wiped Your Phone? Maybe You’ll Go to Prison\\\n[https://www.youtube.com/watch?v=lmikqHw1lX8](https://www.youtube.com/watch?v=lmikqHw1lX8)"
      )

    assert html =~ "Prison<br>\n<a href=\"https://www.youtube.com/watch?v=lmikqHw1lX8\">"
    refute html =~ "Prison\n<a"
    refute html =~ "\\"
  end

  test "renders headings, emphasis, and links" do
    html = Markdown.to_html("# Title\n\nHello **world** and [here](https://example.com).")

    assert html =~ "<h1>Title</h1>"
    assert html =~ "<strong>world</strong>"
    assert html =~ ~s(<a href="https://example.com">here</a>)
  end

  test "does not treat a space before a closing marker as emphasis" do
    html = Markdown.to_html("*Patrik Baab: *\n\n*foo*")

    refute html =~ "<em>Patrik Baab:"
    assert html =~ "*Patrik Baab: *"
    assert html =~ "<em>foo</em>"
  end

  test "does not treat a space after an opening marker as emphasis" do
    html = Markdown.to_html("x * foo*")

    refute html =~ "<em>"
    assert html =~ "* foo*"
  end

  test "renders *** as bold italic" do
    html = Markdown.to_html("***bold italic***")

    assert html =~ "<strong><em>bold italic</em></strong>"
    refute html =~ "***"
  end

  test "renders underscore italic next to bold without leftover markers" do
    md =
      "_To access this week’s edition of **The Corbett Report**_ **Subscriber**_, please [sign in](https://corbettreport.com/login/) and continue reading below._"

    html = Markdown.to_html(md)

    assert html =~ "<em>To access this week’s edition of <strong>The Corbett Report</strong></em>"
    assert html =~ "<strong>Subscriber</strong>"

    assert html =~
             "<em>, please <a href=\"https://corbettreport.com/login/\">sign in</a> and continue reading below.</em>"

    refute html =~ "*"
    refute html =~ "_"
  end

  test "renders italic wrapping a bold link" do
    md =
      "*read the full newsletter or **[ACCESS THE EDITORIAL FOR FREE](https://corbettreport.substack.com/) on my Substack**.*"

    html = Markdown.to_html(md)

    assert html =~ "<em>"
    assert html =~ "<strong>"
    assert html =~ ~s(href="https://corbettreport.substack.com/")
    assert html =~ "ACCESS THE EDITORIAL FOR FREE"
    refute html =~ "*"
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

  test "renders an image inside a link" do
    html =
      Markdown.to_html(
        "[Folgt mir auf Telegram ![](https://cdn.jsdelivr.net/npm/@fortawesome/fontawesome-free@6.7.2/svgs/brands/telegram.svg)](https://t.me/kulturzentner)"
      )

    assert html =~ ~s(<a href="https://t.me/kulturzentner">)

    assert html =~
             ~s(<img src="https://cdn.jsdelivr.net/npm/@fortawesome/fontawesome-free@6.7.2/svgs/brands/telegram.svg" alt="">)

    assert html =~ ~r/Folgt mir auf Telegram.*<img /s
  end

  test "renders an image title as a visible caption" do
    html = Markdown.to_html("![](https://example.com/pic.jpg \"Ashot Grigorian\")")

    assert html =~ "<figure>"
    assert html =~ ~s(<img src="https://example.com/pic.jpg" alt="">)
    assert html =~ "<figcaption>Ashot Grigorian</figcaption>"
    refute html =~ "<p><figure>"
  end

  test "renders image titles that contain apostrophes and ampersands" do
    html =
      Markdown.to_html(
        "![](https://example.com/pic.jpg \"O'Brien & Sons\")"
      )

    assert html =~ "<figure>"
    assert html =~ "<figcaption>O&#39;Brien &amp; Sons</figcaption>"
    refute html =~ "![]("
  end

  test "renders a linked image with a quoted title subtitle" do
    html =
      Markdown.to_html(
        "[![\"Title\"](https://example.com/pic.jpg \"'Title'\")](https://example.com/post)"
      )

    assert html =~ ~s(<a href="https://example.com/post">)
    assert html =~ "<figure>"
    assert html =~ ~s(<img src="https://example.com/pic.jpg")
    assert html =~ "<figcaption>"
    refute html =~ "!["
  end

  test "escapes raw HTML and drops javascript URLs" do
    html = Markdown.to_html("Click [x](javascript:alert(1)) and <script>alert(1)</script>")

    refute html =~ "<script>"
    refute html =~ "javascript:"
    assert html =~ "&lt;script&gt;"
  end

  test "renders mailto links and strips encoded spaces in the address" do
    html =
      Markdown.to_html("[Anmeldung](mailto:%20freie-medienakademie@posteo.de)")

    assert html =~ ~s(<a href="mailto:freie-medienakademie@posteo.de">Anmeldung</a>)
    refute html =~ "%20"
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

  test "renders blank lines inside a blockquote as separate paragraphs" do
    html =
      Markdown.to_html("""
      > IBAN: DE85  
      > _Verwendungszweck: Spende_
      >
      > [Spende via Paypal](https://paypal.me/eugenzentner)
      """)

    assert html =~ "<blockquote>"
    assert html =~ "<p>IBAN: DE85<br>\n<em>Verwendungszweck: Spende</em></p>"
    assert html =~ ~s(<p><a href="https://paypal.me/eugenzentner">Spende via Paypal</a></p>)
  end
end
