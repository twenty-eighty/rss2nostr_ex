defmodule Rss2Nostr.Processing.Sites.CorbettTest do
  use ExUnit.Case, async: true

  alias Rss2Nostr.Processing.{Composer, HtmlToMarkdown, Sites, Youtube}

  defp convert(html, opts) do
    html
    |> Sites.preprocess(opts)
    |> HtmlToMarkdown.convert(skip_classes: [])
  end

  describe "applies?/1" do
    test "matches Corbett hosts and the body-markup selector" do
      assert Sites.Corbett.applies?(%{url: "https://www.corbettreport.com/nwnw639/"})
      assert Sites.Corbett.applies?(%{url: "https://corbettreport.com/nwnw639/"})
      assert Sites.Corbett.applies?(%{body_selector: "div.et_pb_column_0_tb_body"})
      refute Sites.Corbett.applies?(%{url: "https://www.heise.de/news/foo"})
      refute Sites.Corbett.applies?(%{body_selector: "div.entry-content"})
    end
  end

  describe "WATCH ON rows" do
    test "puts each platform link on its own line" do
      html = """
      <p>Intro</p>
      <p><strong>WATCH ON: <a href="https://archive.org/details/x"><img alt="ARCHIVE"></a> /
      <a href="https://odysee.com/@c/z"><img alt="ODYSEE"></a></strong></p>
      """

      md = convert(html, url: "https://www.corbettreport.com/nwnw639/")

      assert md =~ "**WATCH ON:**"
      assert md =~ "[ARCHIVE](https://archive.org/details/x)\n\n[ODYSEE](https://odysee.com/@c/z)"
    end

    test "omits a WATCH ON link that already came from an iframe" do
      html = """
      <p><iframe id="odysee-iframe" src="https://odysee.com/%24/embed/%40corbettreport%3A0%2Fnwnw639%3A9?r=9AWxE8ctoPysNh6rne4ACuTaD8BJiPuH"></iframe></p>
      <p>WATCH ON:
        <a href="https://odysee.com/@corbettreport/nwnw639">Odysee</a> /
        <a href="https://archive.org/details/nwnw639">ARCHIVE</a>
      </p>
      """

      md = convert(html, url: "https://corbettreport.com/nwnw639/")

      assert md =~ "[Watch on Odysee](https://odysee.com/@corbettreport:0/nwnw639:9)"
      refute md =~ "[Odysee](https://odysee.com/@corbettreport/nwnw639)"
      assert md =~ "[ARCHIVE](https://archive.org/details/nwnw639)"
      assert md =~ "**WATCH ON:**"
    end

    test "drops the WATCH ON row when every link is already an iframe" do
      html = """
      <p><iframe src="https://odysee.com/$/embed/@corbettreport:0/nwnw639:9"></iframe></p>
      <p>WATCH ON: <a href="https://odysee.com/@corbettreport/nwnw639">Odysee</a></p>
      """

      md = convert(html, body_selector: "div.et_pb_column_0_tb_body")

      assert md =~ "[Watch on Odysee](https://odysee.com/@corbettreport:0/nwnw639:9)"
      refute md =~ "WATCH ON"
    end

    test "labels a YouTube WATCH ON link as YOUTUBE even when the title is in the HTML" do
      html = """
      <p>WATCH ON:
        <a href="https://www.youtube.com/watch?v=bLA0a0xiy_g">New World Next Week</a> /
        <a href="https://archive.org/details/nwnw639">ARCHIVE</a>
      </p>
      """

      md = convert(html, url: "https://www.corbettreport.com/nwnw639/")

      assert md =~ "[YOUTUBE](https://www.youtube.com/watch?v=bLA0a0xiy_g)"
      refute md =~ "New World Next Week"
      assert md =~ "[ARCHIVE](https://archive.org/details/nwnw639)"
    end

    test "recognizes Watch on without a colon" do
      html = """
      <p><iframe src="https://rumble.com/embed/v3twk6p/?pub=4/"></iframe></p>
      <p><strong>Watch on&nbsp;Archive&nbsp;/&nbsp;<a href="https://www.bitchute.com/video/iLKkpT0PWPdr/">BitChute</a>&nbsp;</strong><strong>/&nbsp;<a href="https://odysee.com/@corbettreport:0/flashback-gaslight:6">Odysee</a>&nbsp;/&nbsp;</strong><strong><a href="https://rokfin.com/post/155830/Gaslight">Rokfin</a>&nbsp;</strong><strong>/&nbsp;<a href="https://rumble.com/v3whxvy-gaslight.html">Rumble</a> / <a href="https://youtu.be/LBl_KJ5-14E">YouTube</a></strong></p>
      """

      md = convert(html, url: "https://corbettreport.com/gaslight-flnwo-08/")

      assert md =~ "**WATCH ON:**"
      assert md =~ "[BitChute](https://www.bitchute.com/video/iLKkpT0PWPdr/)"
      assert md =~ "[Odysee](https://odysee.com/@corbettreport:0/flashback-gaslight:6)"
      assert md =~ "[Rokfin](https://rokfin.com/post/155830/Gaslight)"
      assert md =~ "[YOUTUBE](https://youtu.be/LBl_KJ5-14E)"
      refute md =~ "Watch on Archive"
    end

    test "recognizes Watch this video on platform links" do
      html = """
      <p><iframe src="https://www.youtube.com/embed/UvfJkqF1g6w"></iframe></p>
      <p>Watch this video on <a href="https://www.bitchute.com/video/UvfJkqF1g6w/">BitChute</a> /
      <a href="https://www.minds.com/newsfeed/1034481282948030464">Minds.com</a> /
      <a href="https://youtu.be/UvfJkqF1g6w">YouTube</a> or
      <a href="https://www.corbettreport.com/mp4/flnwo07.mp4">Download the mp4</a></p>
      """

      md = convert(html, url: "https://corbettreport.com/the-lord-of-the-rings-flnwo-07/")

      assert md =~ "**WATCH ON:**"
      assert md =~ "[BitChute](https://www.bitchute.com/video/UvfJkqF1g6w/)"
      assert md =~ "[Minds.com](https://www.minds.com/newsfeed/1034481282948030464)"
      assert md =~ "[Download the mp4](https://www.corbettreport.com/mp4/flnwo07.mp4)"
      refute md =~ "Watch this video on"
      refute md =~ "[YouTube](https://youtu.be/UvfJkqF1g6w)"
      refute md =~ "[YOUTUBE](https://youtu.be/UvfJkqF1g6w)"
    end

    test "does not rewrite a Watch show-note with one video link" do
      html = """
      <p>Watch the congressional hearing: <a href="https://www.youtube.com/watch?v=abc123">Hearing</a></p>
      """

      md = convert(html, url: "https://corbettreport.com/gaslight-flnwo-08/")

      refute md =~ "**WATCH ON:**"
      assert md =~ "Watch the congressional hearing"
      assert md =~ "https://www.youtube.com/watch?v=abc123"
    end

    test "recognizes Watch it on with two platform links" do
      html = """
      <p>Watch it on <a href="https://www.bitchute.com/video/x">BitChute</a> /
      <a href="https://odysee.com/@c/z">Odysee</a></p>
      """

      md = convert(html, url: "https://corbettreport.com/the-lord-of-the-rings-flnwo-07/")

      assert md =~ "**WATCH ON:**"

      assert md =~
               "[BitChute](https://www.bitchute.com/video/x)\n\n[Odysee](https://odysee.com/@c/z)"
    end

    test "does not rewrite WATCH ON on other sites" do
      html = """
      <p>WATCH ON: <a href="https://archive.org/details/x">ARCHIVE</a> /
      <a href="https://odysee.com/@c/z">ODYSEE</a></p>
      """

      md = convert(html, url: "https://example.com/post")

      assert md =~ "WATCH ON"
      refute md =~ "[ARCHIVE](https://archive.org/details/x)\n\n[ODYSEE]"
    end
  end

  test "Composer applies Corbett WATCH ON splitting from the article URL" do
    html = """
    <div class="et_pb_column_0_tb_body">
      <p>WATCH ON: <a href="https://archive.org/details/x">ARCHIVE</a> /
      <a href="https://odysee.com/@c/z">ODYSEE</a></p>
    </div>
    """

    result =
      Composer.compose(html, %{
        body_selector: "div.et_pb_column_0_tb_body",
        skip_classes: [],
        url: "https://www.corbettreport.com/nwnw639/"
      })

    assert result.markdown =~ "[ARCHIVE](https://archive.org/details/x)\n\n[ODYSEE]"
  end

  test "Composer keeps YOUTUBE as the WATCH ON label after title enrichment" do
    html = """
    <div class="et_pb_column_0_tb_body">
      <p>WATCH ON: <a href="https://www.youtube.com/watch?v=bLA0a0xiy_g">New World Next Week</a></p>
    </div>
    """

    result =
      Composer.compose(html, %{
        body_selector: "div.et_pb_column_0_tb_body",
        skip_classes: [],
        url: "https://www.corbettreport.com/nwnw639/"
      })

    markdown =
      Youtube.enrich_markdown(result.markdown,
        enabled: true,
        fetch: fn _ -> "New World Next Week" end
      )

    assert markdown =~ "[YOUTUBE](https://www.youtube.com/watch?v=bLA0a0xiy_g)"
    refute markdown =~ "[New World Next Week]"
  end
end
