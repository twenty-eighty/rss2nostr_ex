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

    test "keeps substantial same-class wrappers and drops a tiny sibling" do
      story = Enum.map_join(1..100, " ", fn i -> "Storyword#{i}" end)

      html = """
      <section class="post_content" itemprop="articleBody">
        <div class="vc_column-inner">
          <div class="wpb_wrapper">
            <div class="wpb_text_column"><div class="wpb_wrapper"><p>#{story}</p></div></div>
          </div>
        </div>
        <div class="vc_column-inner">
          <div class="wpb_wrapper"><p>Keine neuen Texte verpassen</p></div>
        </div>
      </section>
      """

      {extracted, true} = Composer.extract_body(html, "div.wpb_wrapper")
      assert extracted =~ "Storyword1"
      refute extracted =~ "Keine neuen Texte"
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

    test "keeps a WordPress YouTube figure inside entry-content" do
      html = """
      <div class="entry-content">
        <p>Intro.</p>
        <figure class="wp-block-embed is-provider-youtube wp-block-embed-youtube">
          <div class="wp-block-embed__wrapper">
            <iframe title="Talk"
              data-src="https://www.youtube.com/embed/4pQ8boPNzpY?feature=oembed"
              class="lazyload"></iframe>
          </div>
        </figure>
        <p>Outro.</p>
      </div>
      """

      result = Composer.compose(html, %{body_selector: "div.entry-content", skip_classes: []})

      assert result.markdown =~ "Intro."
      assert result.markdown =~ "[Talk](https://www.youtube.com/watch?v=4pQ8boPNzpY)"
      assert result.markdown =~ "Outro."
    end

    test "translates generated labels using the compose language" do
      html = ~s(<iframe src="https://w.soundcloud.com/player/?url=https%3A//soundcloud.com/a/b"></iframe>)

      result = Composer.compose(html, %{skip_classes: [], language: "de"})

      assert result.markdown =~ "[Auf SoundCloud anhören](https://soundcloud.com/a/b)"
    end

    test "promotes a leading image when none is provided" do
      html = ~s(<p><img src="https://example.com/hero.jpg" alt="Hero"></p><p>Article</p>)
      result = Composer.compose(html, %{skip_classes: []})

      assert result.image == "https://example.com/hero.jpg"
      assert result.markdown =~ "Article"
      refute result.markdown =~ "hero.jpg"
    end

    test "keeps an existing image and leaves a different leading image in the Markdown" do
      html = ~s(<p><img src="https://example.com/hero.jpg" alt="Hero"></p><p>Article</p>)

      result =
        Composer.compose(html, %{
          image: "https://example.com/existing.jpg",
          skip_classes: []
        })

      assert result.image == "https://example.com/existing.jpg"
      assert result.markdown =~ "hero.jpg"
    end

    test "drops a leading WordPress sized variant of the featured image" do
      featured = "https://corbettreport.com/wp-content/uploads/2026/05/japanese_qa-featured.jpg"
      body = "https://corbettreport.com/wp-content/uploads/2026/05/japanese_qa-featured-1024x576.jpg"
      html = ~s(<p><img src="#{body}" alt=""></p><p>At long last, the Japanese edition</p>)

      result = Composer.compose(html, %{image: featured, skip_classes: []})

      assert result.image == featured
      assert result.markdown =~ "At long last"
      refute result.markdown =~ "japanese_qa-featured"
    end

    test "drops a featured-image duplicate after an audio link" do
      featured = "https://corbettreport.com/wp-content/uploads/2014/12/scroogesquare.jpg"
      body = "https://www.corbettreport.com/images/scroogesquare.jpg"

      html = """
      <p><a href="http://www.corbettreport.com/mp3/flnwo22.mp3">Audio</a></p>
      <p><img src="#{body}" alt="">On this edition of Film, Literature and the New World Order</p>
      """

      result = Composer.compose(html, %{image: featured, skip_classes: []})

      assert result.image == featured
      assert result.markdown =~ "On this edition of Film"
      refute result.markdown =~ "scroogesquare"
      refute result.markdown =~ "!["
    end

    test "keeps a same-named image that appears after the opening" do
      featured = "https://corbettreport.com/wp-content/uploads/2014/12/scroogesquare.jpg"
      body = "https://www.corbettreport.com/images/scroogesquare.jpg"

      html = """
      <p>On this edition of Film, Literature and the New World Order we discuss Dickens.</p>
      <p><img src="#{body}" alt="Scrooge"></p>
      """

      result = Composer.compose(html, %{image: featured, skip_classes: []})

      assert result.markdown =~ "scroogesquare"
    end

    test "drops a featured-image duplicate after a short credit line" do
      featured =
        "https://substackcdn.com/image/fetch/$s_!SDk6!,f_auto,q_auto:good,fl_progressive:steep/https%3A%2F%2Fsubstack-post-media.s3.amazonaws.com%2Fpublic%2Fimages%2F6f8ea1c7-4a8c-46b2-a9f4-168fc6f98eb9_1254x1254.jpeg"

      body =
        "https://substack-post-media.s3.amazonaws.com/public/images/6f8ea1c7-4a8c-46b2-a9f4-168fc6f98eb9_1254x1254.jpeg"

      html = """
      <p>Von Martin Graf auf Facebook.</p>
      <p><img src="#{body}" alt=""></p>
      <p>Dieser wurde in den USA geboren und von einer Frau ausgetragen.</p>
      """

      result = Composer.compose(html, %{image: featured, skip_classes: []})

      assert result.image == featured
      assert result.markdown =~ "Von Martin Graf auf Facebook."
      assert result.markdown =~ "Dieser wurde in den USA geboren"
      refute result.markdown =~ "6f8ea1c7-4a8c-46b2-a9f4-168fc6f98eb9"
      refute result.markdown =~ "!["
    end

    test "drops a leading HEIC cover that matches the featured Substack image" do
      featured =
        "https://substackcdn.com/image/fetch/$s_!hCAb!,w_1200,h_675,c_fill,f_jpg,q_auto:good,fl_progressive:steep,g_auto/https%3A%2F%2Fsubstack-post-media.s3.amazonaws.com%2Fpublic%2Fimages%2F2b3449dd-0412-4b83-a3c3-241395e4f6a3_4592x3448.heic"

      html = """
      <html>
        <head>
          <meta property="og:image" content="#{featured}">
        </head>
        <body>
          <div class="body markup">
            <div class="captioned-image-container">
              <figure>
                <a href="#{featured}" class="image-link image2">
                  <img src="https://substackcdn.com/image/fetch/$s_!hCAb!,w_1456,c_limit,f_auto,q_auto:good,fl_progressive:steep/https%3A%2F%2Fsubstack-post-media.s3.amazonaws.com%2Fpublic%2Fimages%2F2b3449dd-0412-4b83-a3c3-241395e4f6a3_4592x3448.heic" alt="">
                </a>
              </figure>
            </div>
            <p>Eine geniale Erkenntnis: Eis ist gesund!</p>
          </div>
        </body>
      </html>
      """

      result =
        Composer.compose(html, %{
          body_selector: ".body.markup",
          url: "https://drwatsonfooddetective.substack.com/p/die-sommer-sensation-eis-ist-gesund"
        })

      assert String.starts_with?(String.trim(result.markdown), "Eine geniale Erkenntnis")
      refute result.markdown =~ "2b3449dd-0412-4b83-a3c3-241395e4f6a3"
      refute result.markdown =~ "!["
    end

    test "drops a leading body image that is the same asset as the featured image" do
      featured =
        "https://substackcdn.com/image/fetch/$s_!A5Ic!,w_1200,h_675,c_fill,f_jpg,q_auto:good/https%3A%2F%2Fsubstack-post-media.s3.amazonaws.com%2Fpublic%2Fimages%2F73510e44-7195-418e-aa14-9e863d228777_1280x512.jpeg"

      body =
        "https://substackcdn.com/image/fetch/$s_!A5Ic!,w_1456,c_limit,f_auto,q_auto:good/https%3A%2F%2Fsubstack-post-media.s3.amazonaws.com%2Fpublic%2Fimages%2F73510e44-7195-418e-aa14-9e863d228777_1280x512.jpeg"

      html = ~s(<p><img src="#{body}" alt=""></p><p>Article body</p>)

      result = Composer.compose(html, %{image: featured, skip_classes: []})

      assert result.image == featured
      assert result.markdown =~ "Article body"
      refute result.markdown =~ "73510e44-7195-418e-aa14-9e863d228777"
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

    test "keeps a space after nested italic around a link through body extract" do
      html = """
      <div class="et_pb_column_0_tb_body">
        <p>When you read <em><i><a href="https://example.com/book">Foucault’s Pendulum</a></i> </em>and saw</p>
      </div>
      """

      result =
        Composer.compose(html, %{
          url: "https://www.corbettreport.com/umberto-ecos-foucaults-pendulum/",
          skip_classes: []
        })

      assert result.markdown =~
               "_[Foucault’s Pendulum](https://example.com/book)_ and saw"
    end

    test "uses the site body selector from the article URL when none is stored" do
      html = """
      <div class="et_pb_column_0_tb_body">
        <p>Welcome to New World Next Week</p>
      </div>
      <aside>
        <h2>FREEDOM</h2>
        <h2>RECENT POSTS</h2>
        <h2>ARCHIVES</h2>
      </aside>
      """

      result =
        Composer.compose(html, %{
          url: "https://www.corbettreport.com/nwnw632/",
          skip_classes: []
        })

      assert result.markdown =~ "Welcome to New World Next Week"
      refute result.markdown =~ "FREEDOM"
      refute result.markdown =~ "RECENT POSTS"
      refute result.markdown =~ "ARCHIVES"
    end

    test "keeps the whole page when auto body selection is off" do
      html = """
      <div class="et_pb_column_0_tb_body"><p>Article</p></div>
      <aside><h2>ARCHIVES</h2></aside>
      """

      result =
        Composer.compose(html, %{
          url: "https://www.corbettreport.com/nwnw632/",
          body_selector_auto: false,
          skip_classes: []
        })

      assert result.markdown =~ "Article"
      assert result.markdown =~ "ARCHIVES"
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

    test "prefixes a video enclosure when the item has no page" do
      item = %{
        content: nil,
        summary: "<p>This week on NWNW.</p>",
        link: nil,
        enclosure_url: "https://www.corbettreport.com/mp4/nwnw640.mp4",
        duration: "23:43",
        enclosure_length: 66_928_694
      }

      assert {:ok, html, "feed"} = Composer.html_for_item(item, %{fetch_source_from: "content"})
      assert html =~ ~s(<a href="https://www.corbettreport.com/mp4/nwnw640.mp4" title="23:43 66928694">Video</a>)
      assert html =~ "This week on NWNW."
    end

    test "prefixes an audio enclosure when the item has no page" do
      item = %{
        content: nil,
        summary: "<p>Episode notes.</p>",
        link: nil,
        enclosure_url: "https://www.corbettreport.com/mp3/flnwo03.mp3",
        duration: "45:12",
        enclosure_length: 49_600_123
      }

      assert {:ok, html, "feed"} = Composer.html_for_item(item, %{fetch_source_from: "content"})
      assert html =~ ~s(<a href="https://www.corbettreport.com/mp3/flnwo03.mp3" title="45:12 49600123">Audio</a>)
      assert html =~ "Episode notes."
    end

    test "translates enclosure labels to the source language" do
      item = %{
        content: nil,
        summary: "<p>Заметки.</p>",
        link: nil,
        enclosure_url: "https://www.corbettreport.com/mp3/flnwo03.mp3"
      }

      source = %Source{fetch_source_from: "content", language: "ru", options: %{}}

      assert {:ok, html, "feed"} = Composer.html_for_item(item, source)
      assert html =~ ">Аудио</a>"
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

  describe "preview_parts/1" do
    test "renders markdown and HTML for each split chunk" do
      parts = Composer.preview_parts([
        %{content: "# One\n\nFirst part"},
        %{content: "# Two\n\nSecond part"}
      ])

      assert length(parts) == 2
      assert hd(parts).index == 1
      assert hd(parts).total == 2
      assert hd(parts).markdown == "# One\n\nFirst part"
      assert hd(parts).html =~ "First part"
      assert List.last(parts).index == 2
      assert List.last(parts).markdown == "# Two\n\nSecond part"
    end
  end

  describe "preview/1" do
    test "requires a feed URL" do
      assert {:error, "Feed URL is required"} = Composer.preview(%{})
    end
  end
end
