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
      assert BodySchema.selector_for_url("https://www.heise.de/news/foo") == "article.akwa-article"
      assert BodySchema.selector_for_url("https://www.corbettreport.com/interview/") ==
               "div.et_pb_column_0_tb_body"
    end

    test "returns nil for unknown hosts" do
      assert BodySchema.schema_for_url("https://example.com/article") == nil
      assert BodySchema.selector_for_url("https://example.com/article") == nil
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
