defmodule Rss2Nostr.Processing.BodySchemaTest do
  use ExUnit.Case, async: true

  alias Rss2Nostr.Processing.BodySchema

  describe "schema_for_url/1" do
    test "preselects Substack from the article host" do
      schema = BodySchema.schema_for_url("https://patrikbaab.substack.com/p/raging-destruction")

      assert schema.selector == ".body.markup"
      assert schema.label =~ "Substack"
    end

    test "matches other known hosts" do
      assert BodySchema.selector_for_url("https://www.heise.de/news/foo") ==
               "article.akwa-article"

      assert BodySchema.selector_for_url("https://www.corbettreport.com/interview/") ==
               "div.et_pb_column_0_tb_body"
    end

    test "returns nil for unknown hosts" do
      assert BodySchema.schema_for_url("https://example.com/article") == nil
      assert BodySchema.selector_for_url("https://example.com/article") == nil
    end
  end

  describe "known_selector?/1" do
    test "recognizes site presets" do
      assert BodySchema.known_selector?(".body.markup")
      assert BodySchema.known_selector?("div.et_pb_column_0_tb_body")
      assert BodySchema.known_selector?("div.wpb_wrapper")
      assert BodySchema.known_selector?(".vc_column-inner > .wpb_wrapper")
      refute BodySchema.known_selector?("div.custom-body")
      refute BodySchema.known_selector?("")
    end
  end

  describe "candidates/2" do
    test "recommends the URL schema when that region exists" do
      html = """
      <article>
        <div class="post-header"><p>Chrome</p></div>
        <div class="body markup"><p>Lecture before the New Society</p><p>More words here.</p></div>
      </article>
      """

      regions =
        BodySchema.candidates(html,
          url: "https://patrikbaab.substack.com/p/raging-destruction"
        )

      recommended = Enum.find(regions, & &1.recommended)
      assert recommended.selector == ".body.markup"
      assert recommended.selected
      assert recommended.first_line =~ "Lecture before the New Society"
      assert recommended.word_count > 0
    end

    test "includes the whole page" do
      html = "<article><p>Hello</p></article>"
      regions = BodySchema.candidates(html, url: "https://example.com/a")

      assert Enum.any?(regions, &(&1.selector == "" and &1.label == "Whole page"))
    end

    test "offers WPBakery regions and prefers them over articleBody" do
      story =
        Enum.map_join(1..100, " ", fn i -> "Storyword#{i}" end)

      html = """
      <nav>Menu chrome</nav>
      <section class="post_content" itemprop="articleBody">
        <div class="vc_row wpb_row vc_row-fluid">
          <div class="wpb_column">
            <div class="vc_column-inner">
              <div class="wpb_wrapper">
                <div class="wpb_text_column">
                  <div class="wpb_wrapper"><p>#{story}</p></div>
                </div>
              </div>
            </div>
          </div>
        </div>
        <div class="vc_row wpb_row vc_row-has-fill">
          <div class="wpb_column">
            <div class="vc_column-inner">
              <div class="wpb_wrapper">
                <h3>Keine neuen Texte verpassen</h3>
                <p>Newsletter signup</p>
              </div>
            </div>
          </div>
        </div>
      </section>
      <section class="related_wrap"><h3>Related Posts</h3></section>
      """

      regions = BodySchema.candidates(html, url: "https://example.com/article")
      selectors = Enum.map(regions, & &1.selector)
      recommended = Enum.find(regions, & &1.recommended)
      article_body = Enum.find(regions, &(&1.selector == "[itemprop='articleBody']"))

      assert "" in selectors
      assert article_body
      assert ".vc_column-inner > .wpb_wrapper" in selectors
      assert "div.wpb_wrapper" in selectors

      assert recommended.selector in [
               ".vc_column-inner > .wpb_wrapper",
               "div.wpb_wrapper",
               "div.wpb_text_column"
             ]

      assert recommended.label =~ "WPBakery"
      assert recommended.word_count < article_body.word_count
      refute recommended.first_line =~ "Keine neuen Texte"
      refute recommended.first_line =~ "Related Posts"
    end

    test "prefers WordPress entry-content over a sidebar tab-content widget" do
      story = Enum.map_join(1..80, " ", fn i -> "Storyword#{i}" end)

      popular =
        Enum.map_join(1..40, " ", fn i ->
          "PopularTitle#{i} 2. September 2021"
        end)

      html = """
      <div id="content">
        <main>
          <article>
            <div class="entry-content"><p>#{story}</p></div>
          </article>
        </main>
        <aside>
          <div class="tab-content clearfix">
            <div id="bam-popular"><p>#{popular}</p></div>
          </div>
        </aside>
      </div>
      """

      regions = BodySchema.candidates(html, url: "https://example.com/article")
      recommended = Enum.find(regions, & &1.recommended)
      selectors = Enum.map(regions, & &1.selector)

      assert "div.entry-content" in selectors
      refute "div.tab-content" in selectors
      assert recommended.selector == "div.entry-content"
      assert recommended.label == "WordPress article"
      assert recommended.first_line =~ "Storyword1"
      refute recommended.first_line =~ "PopularTitle"
    end
  end

  describe "apply_start_at/2" do
    test "drops siblings before the matching opening line" do
      html = """
      <div class="body markup">
        <p>Subscribe now</p>
        <p>Lecture before the New Society for Psychology</p>
        <p>On September 28</p>
      </div>
      """

      trimmed =
        BodySchema.apply_start_at(html, "//p[contains(., 'Lecture before the New Society')]")

      refute trimmed =~ "Subscribe now"
      assert trimmed =~ "Lecture before the New Society"
      assert trimmed =~ "On September 28"
    end

    test "leaves HTML unchanged when the xpath misses" do
      html = "<p>Hello</p>"
      assert BodySchema.apply_start_at(html, "//p[contains(., 'Missing')]") == html
    end
  end

  describe "start_blocks/2" do
    test "lists opening paragraphs and headings" do
      html = """
      <p>Subscribe now</p>
      <h2>Introduction</h2>
      <p>Lecture before the New Society</p>
      """

      blocks = BodySchema.start_blocks(html)
      texts = Enum.map(blocks, & &1.text)

      assert "Subscribe now" in texts
      assert "Introduction" in texts
      assert Enum.any?(blocks, &String.contains?(&1.xpath, "Lecture before the New Society"))
    end
  end
end
