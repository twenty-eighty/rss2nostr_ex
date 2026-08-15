defmodule Rss2Nostr.Processing.ComposerTest do
  use ExUnit.Case, async: true

  alias Rss2Nostr.Processing.Composer
  alias Rss2Nostr.Sources.Source

  describe "extract_body/2" do
    test "returns the full HTML when no selector is given" do
      html = "<article><p>Hello</p></article>"
      assert {^html, false} = Composer.extract_body(html, nil)
      assert {^html, false} = Composer.extract_body(html, "")
    end

    test "extracts the matching selector" do
      html = """
      <html><body>
        <nav>Menu</nav>
        <article class="akwa-article"><p>Body text</p></article>
        <footer>Footer</footer>
      </body></html>
      """

      {extracted, true} = Composer.extract_body(html, "article.akwa-article")
      assert extracted =~ "Body text"
      refute extracted =~ "Menu"
    end

    test "falls back to the full HTML when the selector misses" do
      html = "<div class='entry-content'><p>Hello</p></div>"
      {extracted, false} = Composer.extract_body(html, "article.missing")
      assert extracted == html
    end
  end

  describe "compose/2" do
    test "converts selected HTML to Markdown and skips configured classes" do
      html = """
      <div class="entry-content">
        <p>Keep this.</p>
        <div class="OUTBRAIN">Ad block</div>
      </div>
      <aside>Ignore me</aside>
      """

      result =
        Composer.compose(html, %{
          body_selector: "div.entry-content",
          skip_classes: ["OUTBRAIN"]
        })

      assert result.selector_matched
      assert result.markdown =~ "Keep this."
      assert result.html =~ "Keep this."
      refute result.markdown =~ "Ad block"
      refute result.markdown =~ "Ignore me"
    end

    test "promotes a leading image when none is provided" do
      html = ~s(<p><img src="https://example.com/hero.jpg" alt="Hero"></p><p>Article</p>)
      result = Composer.compose(html, %{skip_classes: []})

      assert result.image == "https://example.com/hero.jpg"
      assert result.markdown =~ "Article"
      refute result.markdown =~ "hero.jpg"
    end

    test "keeps an existing image and leaves it in the Markdown" do
      html = ~s(<p><img src="https://example.com/hero.jpg" alt="Hero"></p><p>Article</p>)

      result =
        Composer.compose(html, %{
          image: "https://example.com/existing.jpg",
          skip_classes: []
        })

      assert result.image == "https://example.com/existing.jpg"
      assert result.markdown =~ "hero.jpg"
    end

    test "takes Substack body markup and drops chrome" do
      html = """
      <article>
        <div class="post-header">
          <h1>Raging Destruction</h1>
          <h3>How Media and Hired Scribblers Drive Us into Wars</h3>
          <button>Abonnieren</button>
          <img src="https://example.com/hero.jpg" alt="Hero">
        </div>
        <div class="available-content">
          <div class="body markup">
            <p>Lecture before the New Society for Psychology, 23.03.2026</p>
            <h2 class="header-anchor-post">Introduction: Under Fire
              <div class="header-anchor-parent"><button>Link</button></div>
            </h2>
            <p>On September 28, 2022, our hotel in Donetsk comes under fire.</p>
            <div class="subscription-widget-wrap">
              <p>Dieser Substack wird von den Lesern unterstützt.</p>
              <button>Abonnieren</button>
            </div>
          </div>
        </div>
      </article>
      """

      result = Composer.compose(html, %{body_selector: ".body.markup"})

      assert result.selector_matched
      assert String.starts_with?(String.trim(result.markdown), "Lecture before the New Society")
      assert result.markdown =~ "Introduction: Under Fire"
      assert result.markdown =~ "hotel in Donetsk"
      refute result.markdown =~ "Abonnieren"
      refute result.markdown =~ "Hired Scribblers"
      refute result.markdown =~ "hero.jpg"
      refute result.markdown =~ "Lesern unterstützt"
    end

    test "exposes link-row candidates without applying them" do
      html = """
      <div class="entry-content">
        <p>WATCH ON: <a href="https://archive.org/details/x">ARCHIVE</a> / <a href="https://odysee.com/@c/z">ODYSEE</a></p>
      </div>
      """

      result = Composer.compose(html, %{body_selector: "div.entry-content", skip_classes: []})

      assert Enum.any?(result.link_groups, &String.contains?(&1.xpath, "WATCH ON"))
      refute result.markdown =~ "[ARCHIVE](https://archive.org/details/x)\n\n[ODYSEE]"
    end

    test "drops everything before the start-at line" do
      html = """
      <div class="body markup">
        <p>Subscribe now</p>
        <p>Lecture before the New Society for Psychology</p>
        <p>On September 28, 2022, our hotel in Donetsk comes under fire.</p>
      </div>
      """

      result =
        Composer.compose(html, %{
          body_selector: ".body.markup",
          start_at: "//p[contains(., 'Lecture before the New Society')]",
          skip_classes: []
        })

      assert String.starts_with?(String.trim(result.markdown), "Lecture before the New Society")
      refute result.markdown =~ "Subscribe now"
      assert result.markdown =~ "hotel in Donetsk"
    end
  end

  describe "html_for_item/2" do
    test "uses feed content when fetch_source_from is content" do
      item = %{content: "<p>From feed</p>", summary: nil, link: "https://example.com/a"}
      source = %Source{fetch_source_from: "content", options: %{}}

      assert {:ok, "<p>From feed</p>", "feed"} = Composer.html_for_item(item, source)
    end

    test "uses the summary when content is empty" do
      item = %{content: "", summary: "<p>Summary</p>", link: nil}
      opts = %{fetch_source_from: "content"}

      assert {:ok, "<p>Summary</p>", "feed"} = Composer.html_for_item(item, opts)
    end
  end

  describe "opts_from_source/1" do
    test "reads selector and skip classes from source options" do
      source = %Source{
        fetch_source_from: "content",
        options: %{
          "body_selector" => "article",
          "start_at" => "//p[contains(., 'Hello')]",
          "skip_classes" => ["lead", "OUTBRAIN"]
        }
      }

      opts = Composer.opts_from_source(source)
      assert opts.fetch_source_from == "content"
      assert opts.body_selector == "article"
      assert opts.start_at == "//p[contains(., 'Hello')]"
      assert opts.skip_classes == ["lead", "OUTBRAIN"]
    end

    test "defaults skip classes when options omit them" do
      opts = Composer.opts_from_source(%Source{fetch_source_from: "fetch_from_url", options: %{}})
      assert opts.skip_classes == Composer.default_skip_classes()
    end
  end

  describe "parse_skip_classes/1" do
    test "splits comma and newline lists" do
      assert Composer.parse_skip_classes("lead, OUTBRAIN\nshariff") == [
               "lead",
               "OUTBRAIN",
               "shariff"
             ]
    end
  end

  describe "render_html/1" do
    test "renders Markdown and escapes raw HTML" do
      html = Composer.render_html("Hello **world** and <script>alert(1)</script>")

      assert html =~ "<strong>world</strong>"
      refute html =~ "<script>"
      assert html =~ "&lt;script&gt;"
    end
  end

  describe "preview/1" do
    test "requires a feed URL" do
      assert {:error, "Feed URL is required"} = Composer.preview(%{})
    end
  end
end
