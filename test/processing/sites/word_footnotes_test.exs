defmodule Rss2Nostr.Processing.Sites.WordFootnotesTest do
  use ExUnit.Case, async: true

  alias Rss2Nostr.Processing.{HtmlToMarkdown, Sites}

  defp convert(html, opts \\ []) do
    html
    |> Sites.preprocess(opts)
    |> HtmlToMarkdown.convert()
  end

  test "converts Word endnotes with Roman numerals" do
    html = """
    <p>Konventionalismus.<a href="#_edn1" id="_ednref1">[i]</a></p>
    <p>Mythos.<a href="#_edn2" id="_ednref2">[ii]</a></p>
    <p><a href="#_ednref1" id="_edn1">[i]</a> First note.</p>
    <p><a href="#_ednref2" id="_edn2">[ii]</a> Second note.</p>
    """

    md = convert(html, url: "https://einfachkompliziert.de/autoritarismus-forschung/")

    assert md =~ "Konventionalismus.[^1]"
    assert md =~ "Mythos.[^2]"
    assert md =~ "[^1]: First note."
    assert md =~ "[^2]: Second note."
    assert md =~ "[^1]: First note.\n\n[^2]: Second note."
    refute md =~ "#_edn1"
    refute md =~ "[[i]]"
  end

  test "renumbers restarted Word endnote ids uniquely" do
    html = """
    <p>One.<a href="#_edn1" id="_ednref1">[i]</a></p>
    <p>Two.<a href="#_edn1" id="_ednref1">[i]</a></p>
    <p><a href="#_ednref1" id="_edn1">[i]</a> Alpha.</p>
    <p><a href="#_ednref1" id="_edn1">[i]</a> Beta.</p>
    """

    md = convert(html, url: "https://einfachkompliziert.de/autoritarismus-forschung/")

    assert md =~ "One.[^1]"
    assert md =~ "Two.[^2]"
    assert md =~ "[^1]: Alpha."
    assert md =~ "[^2]: Beta."
  end

  test "keeps a separator after a footnote as its own horizontal rule" do
    html = """
    <p>Cite.<a href="#_edn4" id="_ednref4">[iv]</a></p>
    <p><a href="#_ednref4" id="_edn4">[iv]</a> Note text.)</p>
    <hr class="wp-block-separator">
    <p><a href="#_ednref1" id="_edn1">[i]</a> Next note.</p>
    """

    md = convert(html, url: "https://einfachkompliziert.de/autoritarismus-forschung/")

    assert md =~ "[^4]: Note text.)\n\n---\n\n[^1]: Next note."
    refute md =~ ~r/Note text\.\)[ \t]+---/
    refute md =~ ~r/Note text\.\)\n---/
  end

  test "keeps visible Arabic Word footnote numbers when unique" do
    html = """
    <p>end.<a href="#_ftn43"><sup>[43]</sup></a></p>
    <p><a href="#_ftnref43">[43]</a> Source.</p>
    """

    md = convert(html)

    assert md =~ "end.[^43]"
    assert md =~ "[^43]: Source."
  end
end
