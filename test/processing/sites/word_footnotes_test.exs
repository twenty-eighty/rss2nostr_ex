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

  test "marks bare footnote URLs as links and strips tracking parameters" do
    html = """
    <p>list.<a href="#_ftn2"><sup><span>[2]</span></sup></a></p>
    <p><a href="#_ftnref2"><sup><span>[2]</span></sup></a><span> https://myrotvorets.center/criminal/baab-patrik/</span></p>
    <p>proof.<a href="#_ftn11"><sup><span>[11]</span></sup></a></p>
    <p><a href="#_ftnref11"><sup><span>[11]</span></sup></a><span> Apolut, https://apolut.substack.com/p/leipzig?utm_source=post-email-title&amp;publication_id=9770996&amp;post_id=213826233&amp;isFreemail=true&amp;r=9vuj8&amp;triedRedirect=true&amp;utm_medium=email</span></p>
    <p>note.<a href="#_ftn23"><sup><span>[23]</span></sup></a></p>
    <p><a href="#_ftnref23"><sup><span>[23]</span></sup></a><span> (https://www.archiv-swv.de/pdf-bank/Feinde</span></p>
    <p><span>%20der%20Ukraine.pdf, short https://shorturl.at/k9ta1)</span></p>
    """

    md = convert(html)

    assert md =~
             "[^2]: [https://myrotvorets.center/criminal/baab-patrik/](https://myrotvorets.center/criminal/baab-patrik/)"

    assert md =~
             "[https://apolut.substack.com/p/leipzig](https://apolut.substack.com/p/leipzig)"

    assert md =~
             "([https://www.archiv-swv.de/pdf-bank/Feinde%20der%20Ukraine.pdf](https://www.archiv-swv.de/pdf-bank/Feinde%20der%20Ukraine.pdf), short [https://shorturl.at/k9ta1](https://shorturl.at/k9ta1))"

    refute md =~ "utm_source"
    refute md =~ "isFreemail"
    refute md =~ "triedRedirect"
    refute md =~ "publication_id"
  end

  test "drops a tracking query that a space split off the footnote URL" do
    html = """
    <p>bank.<a href="#_ftn54"><sup><span>[54]</span></sup></a></p>
    <p><a href="#_ftnref54"><sup><span>[54]</span></sup></a><span> https://lauraruggeri.substack.com/p/from-tax-haven?utm_source=post-email title&amp;publication_id=2508626&amp;post_id=206262026&amp;utm_campaign=email-post-title&amp;isFreemail=true&amp;triedRedirect=true&amp;utm_medium=email</span></p>
    """

    md = convert(html)

    assert md =~
             "[^54]: [https://lauraruggeri.substack.com/p/from-tax-haven](https://lauraruggeri.substack.com/p/from-tax-haven)"

    refute md =~ "publication_id"
    refute md =~ "isFreemail"
    refute md =~ "title&"
  end

  test "does not wrap a footnote URL that is already a link" do
    html = """
    <p>end.<a href="#_ftn1"><sup>[1]</sup></a></p>
    <p><a href="#_ftnref1">[1]</a> See <a href="https://example.com/a?utm_source=x">https://example.com/a?utm_source=x</a> and https://example.com/b.</p>
    """

    md = convert(html)

    assert md =~
             "[^1]: See [https://example.com/a](https://example.com/a) and [https://example.com/b](https://example.com/b)."

    refute md =~ "[["
    refute md =~ "utm_source"
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
