defmodule Rss2Nostr.Processing.ConversionTest do
  use ExUnit.Case, async: true

  alias Rss2Nostr.Processing.{Conversion, HtmlToMarkdown}

  @watch_html """
  <p>Intro with a <a href="https://youtube.com/watch?v=abc">video</a> in the text.</p>
  <p><strong>WATCH ON: <a href="https://archive.org/details/x"><img alt="ARCHIVE"></a> /
  <a href="https://www.bitchute.com/video/y/"><img alt="BITCHUTE"></a> /
  <a href="https://odysee.com/@c/z"><img alt="ODYSEE"></a></strong></p>
  """

  @rule %{
    action: "links_as_paragraphs",
    xpath: "//p[contains(., 'WATCH ON:')]",
    label: "alt"
  }

  test "suggests an XPath from distinctive text" do
    {:ok, doc} = Floki.parse_document(@watch_html)
    [p] = Floki.find(doc, "p") |> Enum.filter(&Conversion.matches?(&1, @rule))
    xpath = Conversion.suggest_xpath(p)

    assert xpath == "//p[contains(., 'WATCH ON:')]"
    assert Conversion.describe_xpath(xpath) == "Paragraphs containing “WATCH ON:”"
  end

  test "lists watch-on rows as candidates and ignores inline video links" do
    groups = Conversion.candidates(@watch_html)

    assert Enum.any?(groups, &(&1.xpath == "//p[contains(., 'WATCH ON:')]"))
    refute Enum.any?(groups, fn group ->
             Enum.any?(group.links, &String.contains?(&1.href, "youtube.com"))
           end)
  end

  test "does not split a watch-on row unless a rule is enabled" do
    md = HtmlToMarkdown.convert(@watch_html, skip_classes: [])

    assert md =~ "WATCH ON"
    refute md =~ ~r/\[ARCHIVE\][^\n]*\n\n\[BITCHUTE\]/
  end

  test "splits a matching row into standalone Markdown links" do
    md =
      HtmlToMarkdown.convert(@watch_html,
        skip_classes: [],
        conversion_rules: [@rule]
      )

    assert md =~ "**WATCH ON:**"
    assert md =~ "[ARCHIVE](https://archive.org/details/x)"
    assert md =~ "[BITCHUTE](https://www.bitchute.com/video/y/)"
    assert md =~ "[ODYSEE](https://odysee.com/@c/z)"
    assert md =~ "[ARCHIVE](https://archive.org/details/x)\n\n[BITCHUTE]"
  end

  test "skips not-yet-available links" do
    html =
      "<p>WATCH ON: <a href=\"not yet available\">YouTube</a> <a href=\"https://odysee.com/@c/z\">Odysee</a></p>"

    md =
      HtmlToMarkdown.convert(html,
        skip_classes: [],
        conversion_rules: [@rule]
      )

    refute md =~ "YouTube"
    assert md =~ "[Odysee](https://odysee.com/@c/z)"
  end
end
