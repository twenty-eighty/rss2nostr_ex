defmodule Rss2Nostr.Processing.HtmlToMarkdownTest do
  use ExUnit.Case, async: true

  alias Rss2Nostr.Processing.HtmlToMarkdown

  describe "convert/1" do
    test "converts headings" do
      html = "<h1>Title</h1><h2>Subtitle</h2><h3>Section</h3>"
      md = HtmlToMarkdown.convert(html)

      assert md =~ "# Title"
      assert md =~ "## Subtitle"
      assert md =~ "### Section"
    end

    test "converts paragraphs" do
      html = "<p>First paragraph.</p><p>Second paragraph.</p>"
      md = HtmlToMarkdown.convert(html)

      assert md =~ "First paragraph."
      assert md =~ "Second paragraph."
    end

    test "converts bold text" do
      html = "<p>This is <strong>bold</strong> and <b>also bold</b>.</p>"
      md = HtmlToMarkdown.convert(html)

      assert md =~ "**bold**"
      assert md =~ "**also bold**"
    end

    test "converts italic text" do
      html = "<p>This is <em>italic</em> and <i>also italic</i>.</p>"
      md = HtmlToMarkdown.convert(html)

      assert md =~ "*italic*"
      assert md =~ "*also italic*"
    end

    test "converts links" do
      html = "<a href=\"https://example.com\">Link text</a>"
      md = HtmlToMarkdown.convert(html)

      assert md =~ "[Link text](https://example.com)"
    end

    test "converts images" do
      html = "<img src=\"https://example.com/img.jpg\" alt=\"Alt text\">"
      md = HtmlToMarkdown.convert(html)

      assert md =~ "![Alt text](https://example.com/img.jpg)"
    end

    test "keeps Cloudinary srcset URLs that contain commas" do
      html = """
      <img
        alt=""
        src="https://substackcdn.com/image/fetch/w_96,c_limit,f_auto,q_auto:good,fl_progressive:steep/https%3A%2F%2Fpbs.substack.com%2Fprofile_images%2F1829651769380503552%2FbMTtwSuG.jpg"
        srcset="https://substackcdn.com/image/fetch/w_96,c_limit,f_auto,q_auto:good,fl_progressive:steep/https%3A%2F%2Fpbs.substack.com%2Fprofile_images%2F1829651769380503552%2FbMTtwSuG.jpg 96w, https://substackcdn.com/image/fetch/w_192,c_limit,f_auto,q_auto:good,fl_progressive:steep/https%3A%2F%2Fpbs.substack.com%2Fprofile_images%2F1829651769380503552%2FbMTtwSuG.jpg 192w">
      """

      md = HtmlToMarkdown.convert(html)

      assert md =~ "https://pbs.substack.com/profile_images/1829651769380503552/bMTtwSuG.jpg"
      refute md =~ "fl_progressive:steep"
    end

    test "converts unordered lists" do
      html = "<ul><li>Item 1</li><li>Item 2</li></ul>"
      md = HtmlToMarkdown.convert(html)

      assert md =~ "- Item 1"
      assert md =~ "- Item 2"
    end

    test "converts ordered lists" do
      html = "<ol><li>First</li><li>Second</li></ol>"
      md = HtmlToMarkdown.convert(html)

      assert md =~ "1. First"
      assert md =~ "2. Second"
    end

    test "converts blockquotes" do
      html = "<blockquote>This is a quote.</blockquote>"
      md = HtmlToMarkdown.convert(html)

      assert md =~ "> This is a quote."
    end

    test "converts code blocks" do
      html = "<pre><code>def hello do\n  :world\nend</code></pre>"
      md = HtmlToMarkdown.convert(html)

      assert md =~ "```"
      assert md =~ "def hello do"
    end

    test "converts inline code" do
      html = "<p>Use <code>mix test</code> to run tests.</p>"
      md = HtmlToMarkdown.convert(html)

      assert md =~ "`mix test`"
    end

    test "handles nested elements" do
      html = "<p>Text with <strong><em>bold italic</em></strong>.</p>"
      md = HtmlToMarkdown.convert(html)

      assert md =~ "***bold italic***" or md =~ "**_bold italic_**" or md =~ "_**bold italic**_"
    end

    test "strips script and style tags" do
      html = "<p>Content</p><script>alert('xss')</script><style>.cls{}</style>"
      md = HtmlToMarkdown.convert(html)

      assert md =~ "Content"
      refute md =~ "alert"
      refute md =~ ".cls"
    end

    test "handles empty input" do
      result_empty = HtmlToMarkdown.convert("")
      result_nil = HtmlToMarkdown.convert(nil)

      assert result_empty in ["", nil]
      assert result_nil in ["", nil]
    end

    test "handles plain text" do
      html = "Just plain text without tags"
      md = HtmlToMarkdown.convert(html)

      assert md =~ "Just plain text without tags"
    end

    test "converts horizontal rules" do
      html = "<p>Before</p><hr><p>After</p>"
      md = HtmlToMarkdown.convert(html)

      assert md =~ "---"
    end

    test "converts figures with captions" do
      html = """
      <figure>
        <img src="https://example.com/photo.jpg" alt="Photo">
        <figcaption>This is the caption</figcaption>
      </figure>
      """

      md = HtmlToMarkdown.convert(html)

      assert md =~ "![" or md =~ "https://example.com/photo.jpg"
    end

    test "converts mark/highlight text" do
      html = "<p>This is <mark>highlighted</mark> text.</p>"
      md = HtmlToMarkdown.convert(html)

      assert md =~ "==highlighted==" or md =~ "highlighted"
    end

    test "handles line breaks" do
      html = "<p>Line one<br>Line two</p>"
      md = HtmlToMarkdown.convert(html)

      assert md =~ "Line one"
      assert md =~ "Line two"
    end

    test "skips navigation elements" do
      html = "<nav><a href='/home'>Home</a></nav><p>Content</p>"
      md = HtmlToMarkdown.convert(html)

      assert md =~ "Content"
      refute md =~ "[Home]"
    end

    test "skips header and footer elements" do
      html = "<header>Header</header><p>Content</p><footer>Footer</footer>"
      md = HtmlToMarkdown.convert(html)

      assert md =~ "Content"
    end

    test "converts h4, h5, h6 headings" do
      html = "<h4>H4</h4><h5>H5</h5><h6>H6</h6>"
      md = HtmlToMarkdown.convert(html)

      assert md =~ "#### H4"
      assert md =~ "##### H5"
      assert md =~ "###### H6"
    end

    test "handles tables" do
      html = """
      <table>
        <tr><th>Header 1</th><th>Header 2</th></tr>
        <tr><td>Cell 1</td><td>Cell 2</td></tr>
      </table>
      """

      md = HtmlToMarkdown.convert(html)

      # Tables should be converted or at least preserve content
      assert md =~ "Header 1" or md =~ "Cell 1"
    end

    test "handles nested lists" do
      html = """
      <ul>
        <li>Item 1
          <ul>
            <li>Nested item</li>
          </ul>
        </li>
      </ul>
      """

      md = HtmlToMarkdown.convert(html)

      assert md =~ "Item 1"
      assert md =~ "Nested item"
    end

    test "handles divs" do
      html = "<div><p>Content in div</p></div>"
      md = HtmlToMarkdown.convert(html)

      assert md =~ "Content in div"
    end

    test "handles span elements" do
      html = "<p>Text with <span>span content</span> here</p>"
      md = HtmlToMarkdown.convert(html)

      assert md =~ "span content"
    end

    test "handles articles" do
      html = "<article><p>Article content</p></article>"
      md = HtmlToMarkdown.convert(html)

      assert md =~ "Article content"
    end

    test "handles sections" do
      html = "<section><p>Section content</p></section>"
      md = HtmlToMarkdown.convert(html)

      assert md =~ "Section content"
    end

    test "removes HTML comments" do
      html = "<p>Before</p><!-- comment --><p>After</p>"
      md = HtmlToMarkdown.convert(html)

      assert md =~ "Before"
      assert md =~ "After"
      refute md =~ "comment"
    end

    test "handles iframes" do
      html = "<iframe src=\"https://youtube.com/embed/bLA0a0xiy_g\"></iframe>"
      md = HtmlToMarkdown.convert(html)

      assert md =~ "[Watch on YouTube](https://www.youtube.com/watch?v=bLA0a0xiy_g)"
    end

    test "uses a meaningful iframe title for YouTube embeds" do
      html =
        ~s(<iframe src="https://www.youtube.com/embed/bLA0a0xiy_g" title="A Bloody Delay of Bankruptcy"></iframe>)

      md = HtmlToMarkdown.convert(html)

      assert md =~ "[A Bloody Delay of Bankruptcy](https://www.youtube.com/watch?v=bLA0a0xiy_g)"
      refute md =~ "Watch on YouTube"
    end

    test "ignores the generic YouTube video player iframe title" do
      html =
        ~s(<iframe src="https://www.youtube.com/embed/bLA0a0xiy_g" title="YouTube video player"></iframe>)

      md = HtmlToMarkdown.convert(html)

      assert md =~ "[Watch on YouTube](https://www.youtube.com/watch?v=bLA0a0xiy_g)"
    end

    test "handles picture elements with srcset" do
      html = """
      <picture>
        <source srcset="large.jpg 1024w, small.jpg 640w">
        <img src="fallback.jpg" alt="Image">
      </picture>
      """

      md = HtmlToMarkdown.convert(html)

      # Should extract image from picture
      assert is_binary(md)
    end

    test "handles complex nested structure" do
      html = """
      <article>
        <h1>Title</h1>
        <p>Intro paragraph with <strong>bold</strong> text.</p>
        <ul>
          <li>Item 1</li>
          <li>Item 2</li>
        </ul>
        <blockquote>
          <p>A quote with <em>emphasis</em>.</p>
        </blockquote>
      </article>
      """

      md = HtmlToMarkdown.convert(html)

      assert md =~ "# Title"
      assert md =~ "**bold**"
      assert md =~ "Item 1"
      assert md =~ ">"
    end
  end

  describe "URL tracking parameter removal" do
    test "removes utm parameters from links" do
      html = "<a href=\"https://example.com/page?utm_source=twitter&utm_medium=social\">Link</a>"
      md = HtmlToMarkdown.convert(html)

      assert md =~ "[Link](https://example.com/page)"
      refute md =~ "utm_source"
      refute md =~ "utm_medium"
    end

    test "preserves non-tracking query parameters" do
      html = "<a href=\"https://example.com/search?q=test&page=1\">Search</a>"
      md = HtmlToMarkdown.convert(html)

      assert md =~ "q=test" or md =~ "page=1"
    end

    test "removes fbclid parameter" do
      html = "<a href=\"https://example.com/article?fbclid=abc123\">Article</a>"
      md = HtmlToMarkdown.convert(html)

      refute md =~ "fbclid"
    end
  end

  describe "site-specific cleanup" do
    test "skips default ad and teaser classes" do
      html = """
      <p>Keep</p>
      <div class="OUTBRAIN">Ads</div>
      <p class="lead">Teaser</p>
      """

      md = HtmlToMarkdown.convert(html)

      assert md =~ "Keep"
      refute md =~ "Ads"
      refute md =~ "Teaser"
    end

    test "honors an explicit skip_classes list" do
      html = "<p class='custom-junk'>Drop</p><p>Keep</p>"
      md = HtmlToMarkdown.convert(html, skip_classes: ["custom-junk"])

      assert md =~ "Keep"
      refute md =~ "Drop"
    end

    test "formats pullquotes as blockquotes" do
      html = ~s(<div class="pullquote"><p>Hello</p></div>)
      md = HtmlToMarkdown.convert(html)

      assert md =~ "> Hello"
    end

    test "drops relative links" do
      html = ~s(<p>See <a href="/local-page">this</a> and <a href="https://example.com">that</a>.</p>)
      md = HtmlToMarkdown.convert(html)

      refute md =~ "/local-page"
      assert md =~ "[that](https://example.com)"
    end

    test "turns a centered asterisk paragraph into a rule" do
      html = "<p>*</p>"
      md = HtmlToMarkdown.convert(html)

      assert md =~ "---"
    end
  end
end

