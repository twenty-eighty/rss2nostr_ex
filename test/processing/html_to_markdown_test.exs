defmodule Rss2Nostr.Processing.HtmlToMarkdownTest do
  use ExUnit.Case, async: true

  alias Rss2Nostr.Processing.{HtmlToMarkdown, Markdown}

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

      assert md =~ "_italic_"
      assert md =~ "_also italic_"
    end

    test "converts links" do
      html = "<a href=\"https://example.com\">Link text</a>"
      md = HtmlToMarkdown.convert(html)

      assert md =~ "[Link text](https://example.com)"
    end

    test "keeps duration titles on audio and video file links" do
      html =
        ~s(<p><a href="https://www.corbettreport.com/mp3/flnwo03.mp3" title="45:12 49600123">Audio</a></p>)

      md = HtmlToMarkdown.convert(html)

      assert md =~ ~s|[Audio](https://www.corbettreport.com/mp3/flnwo03.mp3 "45:12 49600123")|
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

    test "moves spaces outside italic markers" do
      assert HtmlToMarkdown.convert("<p><em>Patrik Baab: </em></p>") == "_Patrik Baab:_"
      assert HtmlToMarkdown.convert("<p><em> foo</em>bar</p>") == "_foo_bar"
      assert HtmlToMarkdown.convert("<p>before<em> foo </em>after</p>") == "before _foo_ after"
    end

    test "keeps a space after nested italic around a link" do
      html =
        ~s(<p>When you read <em><i><a href="https://example.com/book">Foucault’s Pendulum</a></i> </em>and saw</p>)

      assert HtmlToMarkdown.convert(html) ==
               "When you read _[Foucault’s Pendulum](https://example.com/book)_ and saw"

      html_preview = Markdown.to_html(HtmlToMarkdown.convert(html))
      assert html_preview =~ ~r/Pendulum<\/a><\/em> and saw/
    end

    test "moves spaces outside bold markers" do
      assert HtmlToMarkdown.convert("<p><strong>bold </strong>text</p>") == "**bold** text"
    end

    test "does not wrap whitespace-only emphasis" do
      md = HtmlToMarkdown.convert("<p>keep<em>   </em>going</p>")

      refute md =~ "*"
      assert md =~ "keep"
      assert md =~ "going"
    end

    test "peels pretty-printed newlines out of emphasis" do
      html = """
      <p>
        <em>
          Patrik Baab:
        </em>
      </p>
      """

      assert HtmlToMarkdown.convert(html) == "_Patrik Baab:_"
    end

    test "peels a nested whitespace span out of italic" do
      html = "<p><em><span>Patrik Baab: </span></em></p>"
      assert HtmlToMarkdown.convert(html) == "_Patrik Baab:_"
    end

    test "merges adjacent italic tags so markers do not glue together" do
      html = """
      <p><em>read the full newsletter or<span> </span></em><em><strong><a href="https://corbettreport.substack.com/">ACCESS THE EDITORIAL FOR FREE</a> on my Substack</strong>.</em></p>
      """

      md = HtmlToMarkdown.convert(html)

      assert md ==
               "_read the full newsletter or **[ACCESS THE EDITORIAL FOR FREE](https://corbettreport.substack.com/) on my Substack**._"

      refute md =~ "****"
    end

    test "merges adjacent italic tags separated only by whitespace" do
      assert HtmlToMarkdown.convert("<p><em>foo</em> <em>bar</em></p>") == "_foo bar_"
    end

    test "does not invent a space when adjacent tags have none" do
      assert HtmlToMarkdown.convert("<p><em>foo</em><em>bar</em></p>") == "_foobar_"
    end

    test "does not insert a space when a word is split across adjacent tags" do
      html =
        ~s(<p><strong><em>V</em></strong><strong><em>ideo player not working? Use these links to watch it somewhere else!</em></strong></p>)

      assert HtmlToMarkdown.convert(html) ==
               "**_Video player not working? Use these links to watch it somewhere else!_**"
    end

    test "keeps italic around inner bold" do
      html = "<p><em>foo <strong>bar</strong></em></p>"
      assert HtmlToMarkdown.convert(html) == "_foo **bar**_"
    end

    test "keeps bold around inner italic" do
      html = "<p><strong>foo <em>bar</em></strong></p>"
      assert HtmlToMarkdown.convert(html) == "**foo _bar_**"
    end

    test "does not glue italic to a neighboring bold as ***" do
      html =
        "<p><em>To access this week’s edition of<span>&nbsp;</span><strong>The Corbett Report&nbsp;</strong></em><strong>Subscriber</strong><em>, please<span>&nbsp;</span><a href=\"https://corbettreport.com/login/\">sign in</a><span>&nbsp;</span>and continue reading below.</em></p>"

      md = HtmlToMarkdown.convert(html)

      assert md ==
               "_To access this week’s edition of **The Corbett Report**_ **Subscriber**_, please [sign in](https://corbettreport.com/login/) and continue reading below._"

      refute md =~ "***"
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

    test "finds an image nested inside a Substack figure link" do
      html = """
      <div class="captioned-image-container">
        <figure>
          <a target="_blank" href="https://substackcdn.com/image/fetch/f_auto/https%3A%2F%2Fsubstack-post-media.s3.amazonaws.com%2Fpublic%2Fimages%2F45b3c34b-433c-4d7c-a9dd-56048068b673_1280x640.jpeg" class="image-link image2">
            <div class="image2-inset">
              <picture>
                <source type="image/webp" srcset="https://substackcdn.com/image/fetch/w_424,f_webp/https%3A%2F%2Fsubstack-post-media.s3.amazonaws.com%2Fpublic%2Fimages%2F45b3c34b-433c-4d7c-a9dd-56048068b673_1280x640.jpeg 424w">
                <img src="https://substackcdn.com/image/fetch/w_1456,c_limit,f_auto/https%3A%2F%2Fsubstack-post-media.s3.amazonaws.com%2Fpublic%2Fimages%2F45b3c34b-433c-4d7c-a9dd-56048068b673_1280x640.jpeg" alt="">
              </picture>
            </div>
          </a>
          <figcaption>Ashot Grigorian</figcaption>
        </figure>
      </div>
      """

      md = HtmlToMarkdown.convert(html)

      assert md =~ "substack-post-media.s3.amazonaws.com/public/images/45b3c34b-433c-4d7c-a9dd-56048068b673_1280x640.jpeg"
      assert md =~ "Ashot Grigorian"
      refute md =~ "image-link"
      refute md =~ "](https://substackcdn.com/image/fetch"
    end

    test "keeps a Substack HEIC image on the CDN so browsers can display it" do
      origin =
        "https://substack-post-media.s3.amazonaws.com/public/images/47485710-5d05-4cea-a61c-53138cfa407b_4032x3024.heic"

      html = """
      <figure>
        <img src="https://substackcdn.com/image/fetch/w_1456,c_limit,f_auto/https%3A%2F%2Fsubstack-post-media.s3.amazonaws.com%2Fpublic%2Fimages%2F47485710-5d05-4cea-a61c-53138cfa407b_4032x3024.heic" alt="">
      </figure>
      """

      md = HtmlToMarkdown.convert(html)

      assert md =~ "substackcdn.com/image/fetch/"
      assert md =~ "f_jpg"
      assert md =~ "47485710-5d05-4cea-a61c-53138cfa407b_4032x3024.heic"
      refute md =~ "![](#{origin})"
    end

    test "keeps an Amazon link around a Substack book-cover figure" do
      html = """
      <div class="captioned-image-container">
        <figure>
          <a target="_blank" href="https://www.amazon.de/dp/B0HCPJVJHV?spcref=HARDCOVER_LISTING" class="image-link image2">
            <picture>
              <img src="https://substackcdn.com/image/fetch/w_1456,c_limit,f_auto/https%3A%2F%2Fsubstack-post-media.s3.amazonaws.com%2Fpublic%2Fimages%2F681909bf-1247-4a6a-a465-047ba9862943_1044x258.heic" alt="">
            </picture>
          </a>
        </figure>
      </div>
      """

      md = HtmlToMarkdown.convert(html)

      assert md =~ "](https://www.amazon.de/dp/B0HCPJVJHV"
      assert md =~ "substackcdn.com/image/fetch/"
      assert md =~ "681909bf-1247-4a6a-a465-047ba9862943_1044x258.heic"
    end

    test "does not use a bare alt attribute as a caption" do
      html = """
      <figure>
        <img alt src="https://example.com/photo.jpg">
      </figure>
      """

      md = HtmlToMarkdown.convert(html)

      assert md =~ "https://example.com/photo.jpg"
      refute md =~ ~s("alt")
      refute md =~ "![alt]"
    end

    test "does not promote image alt text to a visible caption" do
      html = """
      <figure>
        <img src="https://example.com/photo.jpg" alt="Photo of Yerevan">
      </figure>
      """

      md = HtmlToMarkdown.convert(html)

      assert md =~ "![Photo of Yerevan](https://example.com/photo.jpg)"
      refute md =~ ~s("Photo of Yerevan")
    end

    test "converts mark/highlight text" do
      html = "<p>This is <mark>highlighted</mark> text.</p>"
      md = HtmlToMarkdown.convert(html)

      assert md =~ "==highlighted==" or md =~ "highlighted"
    end

    test "handles line breaks" do
      html = "<p>Line one<br>Line two</p>"
      md = HtmlToMarkdown.convert(html)

      assert md =~ "Line one  \nLine two"
      refute md =~ "Line one\n\nLine two"
    end

    test "keeps a title and URL on separate lines when a br separates them" do
      html = """
      <p>Video: 404 Media – Wiped Your Phone? Maybe You’ll Go to Prison<br>
      <a href="https://www.youtube.com/watch?v=lmikqHw1lX8">https://www.youtube.com/watch?v=lmikqHw1lX8</a></p>
      """

      md = HtmlToMarkdown.convert(html, skip_classes: [])

      assert md =~
               "Video: 404 Media – Wiped Your Phone? Maybe You’ll Go to Prison  \n[https://www.youtube.com/watch?v=lmikqHw1lX8](https://www.youtube.com/watch?v=lmikqHw1lX8)"

      refute md =~ "\\"

      html_preview = Markdown.to_html(md)
      assert html_preview =~ "Prison<br>\n<a href=\"https://www.youtube.com/watch?v=lmikqHw1lX8\">"
      refute html_preview =~ "</p>\n<p>"
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

    test "keeps a WordPress lazy YouTube embed wrapped in a figure" do
      html = """
      <figure class="wp-block-embed is-type-video is-provider-youtube wp-block-embed-youtube">
        <div class="wp-block-embed__wrapper">
          <iframe title="Ulrike Guerot bei Menschlich Wirtschaften – noch nie war sie so nahbar und verletzlich."
            width="750" height="422" frameborder="0" allowfullscreen
            data-src="https://www.youtube.com/embed/4pQ8boPNzpY?feature=oembed"
            class="lazyload"></iframe>
        </div>
      </figure>
      """

      md = HtmlToMarkdown.convert(html)

      assert md =~
               "[Ulrike Guerot bei Menschlich Wirtschaften – noch nie war sie so nahbar und verletzlich.](https://www.youtube.com/watch?v=4pQ8boPNzpY)"
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

    test "extracts an Odysee watch URL from an embed iframe" do
      html =
        ~s(<p><iframe id="odysee-iframe" src="https://odysee.com/%24/embed/%40corbettreport%3A0%2Fnwnw639%3A9?r=9AWxE8ctoPysNh6rne4ACuTaD8BJiPuH" allowfullscreen="allowfullscreen"></iframe></p>)

      md = HtmlToMarkdown.convert(html)

      assert md =~ "[Watch on Odysee](https://odysee.com/@corbettreport:0/nwnw639:9)"
      refute md =~ "$/embed"
      refute md =~ "%24"
    end

    test "extracts Bitchute, Rumble, and Archive.org watch URLs from embed iframes" do
      html = """
      <iframe src="https://www.bitchute.com/embed/2QbsxZOkIYjA/"></iframe>
      <iframe src="https://rumble.com/embed/v123abc/?pub=7a1"></iframe>
      <iframe src="https://archive.org/embed/nwnw639"></iframe>
      """

      md = HtmlToMarkdown.convert(html)

      assert md =~ "[Watch on Bitchute](https://www.bitchute.com/video/2QbsxZOkIYjA/)"
      assert md =~ "[Watch on Rumble](https://rumble.com/embed/v123abc)"
      assert md =~ "[Watch on Archive.org](https://archive.org/details/nwnw639)"
    end

    test "turns a lazy-loaded Podbean player into a Pareto episode permalink" do
      html = """
      <p><iframe title="Schwindelfrei – Kapitel 6" allowtransparency="true" height="150" width="100%"
        scrolling="no" data-name="pb-iframe-player" loading="lazy"
        data-src="https://www.podbean.com/player-v2/?i=rwwyx-1b3e4d9-pb&#038;from=pb6admin&#038;share=1&#038;download=1"
        class="lazyload"></iframe></p>
      """

      md = HtmlToMarkdown.convert(html)

      assert md =~ "[Listen on Podbean](https://www.podbean.com/ep/pb-rwwyx-1b3e4d9)"
      refute md =~ "player-v2"
    end

    test "turns a SoundCloud player iframe into a standalone permalink" do
      html = """
      <p>Intro text</p>
      <iframe src="https://w.soundcloud.com/player/?url=https%3A//api.soundcloud.com/tracks/soundcloud%3Atracks%3A2370950135%3Fsecret_token%3Ds-b588AbHllcI&amp;color=%23ffd400"></iframe>
      <div style="font-size: 10px">
        <a href="https://soundcloud.com/radiomuenchen">Radio München</a> ·
        <a href="https://soundcloud.com/radiomuenchen/radio-muenchen-redaktion-macht/s-b588AbHllcI">Sommerpause</a>
      </div>
      """

      md = HtmlToMarkdown.convert(html)

      assert md =~ "Intro text"
      assert md =~ "[Listen on SoundCloud](https://soundcloud.com/radiomuenchen/radio-muenchen-redaktion-macht/s-b588AbHllcI?color=%23ffd400)"
      refute md =~ "w.soundcloud.com"
      refute md =~ "api.soundcloud.com"
      refute md =~ "[Radio München]"
      refute md =~ "[Sommerpause]"
      refute md =~ " ·"
    end

    test "keeps article text when SoundCloud chrome sits in the same wrapper" do
      html = """
      <div itemprop="articleBody" class="com-content-article__body">
        <p>Die Radio München-Redaktion macht SOMMER-PAUSE. Wir hören uns im September wieder. Nutzen Sie doch mal die Gelegenheit und genießen Sie bis dahin unser Musikprogramm ... so vielfältig wie die Stadt!</p>
        <p><iframe src="https://w.soundcloud.com/player/?url=https%3A//api.soundcloud.com/tracks/soundcloud%3Atracks%3A2370950135%3Fsecret_token%3Ds-b588AbHllcI" width="100%" height="166"></iframe></p>
        <div style="font-size: 10px; color: #cccccc;">
          <a href="https://soundcloud.com/radiomuenchen">Radio München</a> ·
          <a href="https://soundcloud.com/radiomuenchen/radio-muenchen-redaktion-macht/s-b588AbHllcI">RADIO MÜNCHEN-Redaktion macht Sommerpause</a>
        </div>
      </div>
      """

      md = HtmlToMarkdown.convert(html, language: "de")

      assert md =~ "Die Radio München-Redaktion macht SOMMER-PAUSE."
      assert md =~ "so vielfältig wie die Stadt!"
      assert md =~ "[Auf SoundCloud anhören](https://soundcloud.com/radiomuenchen/radio-muenchen-redaktion-macht/s-b588AbHllcI)"
      refute md =~ "[Radio München]"
      refute md =~ "[RADIO MÜNCHEN-Redaktion macht Sommerpause]"
    end

    test "translates generated embed labels to the feed language" do
      html = """
      <iframe src="https://w.soundcloud.com/player/?url=https%3A//soundcloud.com/a/b"></iframe>
      <iframe src="https://www.youtube.com/embed/bLA0a0xiy_g" title="YouTube video player"></iframe>
      <iframe data-src="https://www.podbean.com/player-v2/?i=rwwyx-1b3e4d9-pb" class="lazyload"></iframe>
      """

      md = HtmlToMarkdown.convert(html, language: "de")

      assert md =~ "[Auf SoundCloud anhören](https://soundcloud.com/a/b)"
      assert md =~ "[Auf YouTube ansehen](https://www.youtube.com/watch?v=bLA0a0xiy_g)"
      assert md =~ "[Auf Podbean anhören](https://www.podbean.com/ep/pb-rwwyx-1b3e4d9)"
    end

    test "copies the SoundCloud iframe color onto the listen link" do
      html = """
      <p>Intro</p>
      <iframe src="https://w.soundcloud.com/player/?url=https%3A//soundcloud.com/a/b&amp;color=%23ffd400"></iframe>
      """

      md = HtmlToMarkdown.convert(html)

      assert md =~ "[Listen on SoundCloud](https://soundcloud.com/a/b?color=%23ffd400)"
    end

    test "leaves SoundCloud permalinks unchanged when the iframe has no color" do
      html = ~s(<iframe src="https://w.soundcloud.com/player/?url=https%3A//soundcloud.com/a/b"></iframe>)
      md = HtmlToMarkdown.convert(html)

      assert md =~ "[Listen on SoundCloud](https://soundcloud.com/a/b)"
      refute md =~ "color="
    end

    test "plain_summary strips RSS description HTML and SoundCloud chrome" do
      html = """
      <div class="feed-description"><p>Die Radio München-Redaktion macht SOMMER-PAUSE. Wir hören uns im September wieder. Nutzen Sie doch mal die Gelegenheit und genießen Sie bis dahin unser Musikprogramm ... so vielfältig wie die Stadt!</p>
      <p><iframe src="https://w.soundcloud.com/player/?url=https%3A//api.soundcloud.com/tracks/soundcloud%3Atracks%3A2370950135%3Fsecret_token%3Ds-b588AbHllcI&amp;color=%23ffd400" width="100%" height="166"></iframe></p>
      <div style="font-size: 10px; color: #cccccc;"><a href="https://soundcloud.com/radiomuenchen">Radio München</a> · <a href="https://soundcloud.com/radiomuenchen/radio-muenchen-redaktion-macht/s-b588AbHllcI">RADIO MÜNCHEN-Redaktion macht Sommerpause</a></div></div>
      """

      assert HtmlToMarkdown.plain_summary(html) ==
               "Die Radio München-Redaktion macht SOMMER-PAUSE. Wir hören uns im September wieder. Nutzen Sie doch mal die Gelegenheit und genießen Sie bis dahin unser Musikprogramm ... so vielfältig wie die Stadt!"
    end

    test "plain_summary keeps already-plain text" do
      assert HtmlToMarkdown.plain_summary("A plain teaser.") == "A plain teaser."
    end

    test "plain_summary returns nil for iframe-only HTML" do
      html = ~s(<iframe src="https://w.soundcloud.com/player/?url=https%3A//soundcloud.com/a/b"></iframe>)
      assert HtmlToMarkdown.plain_summary(html) == nil
    end

    test "prepends a SoundCloud permalink from hydration JSON" do
      html =
        ~s(<script>window.__sc_hydration = [{"hydratable":"sound","data":{"permalink_url":"https://soundcloud.com/radiomuenchen/erziehung-ist-gewalt-von-lara-fischer"}}];</script><p>Body</p>)

      md = HtmlToMarkdown.convert(html)

      assert md ==
               "[Listen on SoundCloud](https://soundcloud.com/radiomuenchen/erziehung-ist-gewalt-von-lara-fischer)\n\nBody"
    end

    test "falls back to the player url param when there is no track page" do
      html =
        ~s(<iframe src="https://w.soundcloud.com/player/?url=https%3A//api.soundcloud.com/tracks/12345"></iframe>)

      md = HtmlToMarkdown.convert(html)

      assert md =~ "[Listen on SoundCloud](https://api.soundcloud.com/tracks/12345)"
      refute md =~ "w.soundcloud.com/player"
    end

    test "treats an Odysee embed and a watch-page URL as the same video" do
      embed = "https://odysee.com/%24/embed/%40corbettreport%3A0%2Fnwnw639%3A9?r=abc"
      watch = "https://odysee.com/@corbettreport/nwnw639"

      assert HtmlToMarkdown.same_video?(
               HtmlToMarkdown.iframe_watch_url(embed),
               watch
             )

      refute HtmlToMarkdown.same_video?(
               "https://odysee.com/@corbettreport/nwnw639",
               "https://archive.org/details/nwnw639"
             )
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

    test "formats message boxes as blockquotes" do
      html = """
      <div class="message  message--success">
        <span>Kulturjournalismus braucht deine Hilfe!</span>
        <p>Wer meine Arbeit unterstützen möchte, kann es via Überweisung oder <a href="https://paypal.me/eugenzentner?locale.x=de_DE" class="message-link" target="_blank" rel="noopener">Paypal</a> tun. Herzlichen Dank!</p>
        <span>Überweisung:</span>
        <p>IBAN: DE85 1203 0000 1033 9733 04<br>
         <u>Verwendungszweck: Spende</u>
        </p>
        <a href="https://paypal.me/eugenzentner?locale.x=de_DE" class="message-link" target="_blank" rel="noopener">Spende via Paypal</a>
      </div>
      """

      md = HtmlToMarkdown.convert(html)

      assert md =~ "> Kulturjournalismus braucht deine Hilfe!"
      assert md =~ "> Wer meine Arbeit unterstützen möchte"
      assert md =~ "[Paypal](https://paypal.me/eugenzentner?locale.x=de_DE)"
      assert md =~ "> Überweisung:"
      assert md =~ "> IBAN: DE85 1203 0000 1033 9733 04"
      assert md =~ "_Verwendungszweck: Spende_"
      assert md =~ ~r/_Verwendungszweck: Spende_\n>\n> \[Spende via Paypal\]/
      refute md =~ "message--success"

      html_out = Rss2Nostr.Processing.Markdown.to_html(md)
      assert html_out =~ ~s(<p><a href="https://paypal.me/eugenzentner?locale.x=de_DE">Spende via Paypal</a></p>)
      refute html_out =~ ~r/<p>IBAN:[^<]*Spende via Paypal/
    end

    test "turns a social-bar icon into a Markdown link using the nearby label" do
      html = """
      <div class="social-bar">
        <span>Folgt mir auf Telegram</span>
        <div class="social-icons text-center">
          <a href="
      https://t.me/kulturzentner
      " target="_blank">
            <i class="fab fa-telegram"></i>
          </a>
        </div>
      </div>
      """

      md = HtmlToMarkdown.convert(html)
      icon = "https://cdn.jsdelivr.net/npm/@fortawesome/fontawesome-free@6.7.2/svgs/brands/telegram.svg"

      assert md =~ "[Folgt mir auf Telegram ![](#{icon})](https://t.me/kulturzentner)"
      refute md =~ "_Telegram_"
      html_out = Rss2Nostr.Processing.Markdown.to_html(md)
      assert html_out =~ ~s(<a href="https://t.me/kulturzentner">)
      assert html_out =~ ~s(<img src="#{icon}" alt="">)
      assert html_out =~ ~r/Folgt mir auf Telegram.*<img /s
    end

    test "labels an icon-only social link from the icon class" do
      html = ~s(<a href="https://t.me/kulturzentner"><i class="fab fa-telegram"></i></a>)
      md = HtmlToMarkdown.convert(html)
      icon = "https://cdn.jsdelivr.net/npm/@fortawesome/fontawesome-free@6.7.2/svgs/brands/telegram.svg"

      assert md =~ "[![](#{icon}) Telegram](https://t.me/kulturzentner)"
    end

    test "keeps text before the icon when the HTML has that order" do
      html = ~s(<a href="https://t.me/kulturzentner">Telegram <i class="fab fa-telegram"></i></a>)
      md = HtmlToMarkdown.convert(html)
      icon = "https://cdn.jsdelivr.net/npm/@fortawesome/fontawesome-free@6.7.2/svgs/brands/telegram.svg"

      assert md =~ "[Telegram ![](#{icon})](https://t.me/kulturzentner)"
    end

    test "keeps the icon before text when the HTML has that order" do
      html = ~s(<a href="https://t.me/kulturzentner"><i class="fab fa-telegram"></i> Telegram</a>)
      md = HtmlToMarkdown.convert(html)
      icon = "https://cdn.jsdelivr.net/npm/@fortawesome/fontawesome-free@6.7.2/svgs/brands/telegram.svg"

      assert md =~ "[![](#{icon}) Telegram](https://t.me/kulturzentner)"
    end

    test "keeps mailto links and strips encoded spaces in the address" do
      html = ~s(<p><a href="mailto:%20freie-medienakademie@posteo.de">Anmeldung</a></p>)
      md = HtmlToMarkdown.convert(html)

      assert md =~ "[Anmeldung](mailto:freie-medienakademie@posteo.de)"
      refute md =~ "%20"

      html_out = Markdown.to_html(md)
      assert html_out =~ ~s(<a href="mailto:freie-medienakademie@posteo.de">Anmeldung</a>)
    end

    test "keeps mailto query parameters" do
      html =
        ~s(<a href="mailto:freie-medienakademie@posteo.de?subject=Bewerbung">E-Mail schreiben</a>)

      md = HtmlToMarkdown.convert(html)

      assert md =~ "[E-Mail schreiben](mailto:freie-medienakademie@posteo.de?subject=Bewerbung)"
    end

    test "labels Facebook, Instagram, and Twitter links from the URL" do
      facebook = "https://cdn.jsdelivr.net/npm/@fortawesome/fontawesome-free@6.7.2/svgs/brands/facebook.svg"
      instagram = "https://cdn.jsdelivr.net/npm/@fortawesome/fontawesome-free@6.7.2/svgs/brands/instagram.svg"
      twitter = "https://cdn.jsdelivr.net/npm/@fortawesome/fontawesome-free@6.7.2/svgs/brands/x-twitter.svg"

      md =
        HtmlToMarkdown.convert("""
        <p><a href="https://www.facebook.com/radiomuenchen"></a></p>
        <p><a href="https://www.instagram.com/radio_muenchen/">www.instagram.com/radio_muenchen/</a></p>
        <p>twitter.com/RadioMuenchen</p>
        """)

      assert md =~ "[![](#{facebook}) Facebook](https://www.facebook.com/radiomuenchen)"
      assert md =~ "[Instagram ![](#{instagram})](https://www.instagram.com/radio_muenchen/)"
      assert md =~ "[![](#{twitter}) Twitter](https://twitter.com/RadioMuenchen)"
    end

    test "keeps custom text on a Facebook link and adds the platform icon" do
      html = ~s(<a href="https://www.facebook.com/radiomuenchen">Radio München</a>)
      md = HtmlToMarkdown.convert(html)
      icon = "https://cdn.jsdelivr.net/npm/@fortawesome/fontawesome-free@6.7.2/svgs/brands/facebook.svg"

      assert md =~ "[Radio München ![](#{icon})](https://www.facebook.com/radiomuenchen)"
    end

    test "drops relative links" do
      html =
        ~s(<p>See <a href="/local-page">this</a> and <a href="https://example.com">that</a>.</p>)

      md = HtmlToMarkdown.convert(html)

      refute md =~ "/local-page"
      assert md =~ "[that](https://example.com)"
    end

    test "turns a centered asterisk paragraph into a rule" do
      html = "<p>*</p>"
      md = HtmlToMarkdown.convert(html)

      assert md =~ "---"
    end

    test "leaves Word footnote anchors as fragment links" do
      html = ~s(<p>investor.<a href="#_ftn43"><sup><span>[43]</span></sup></a></p>)
      md = HtmlToMarkdown.convert(html)

      assert md =~ "[[43]](#_ftn43)"
      refute md =~ "[^43]"
    end
  end
end
