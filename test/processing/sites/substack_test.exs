defmodule Rss2Nostr.Processing.Sites.SubstackTest do
  use ExUnit.Case, async: true

  alias Rss2Nostr.Processing.{Composer, HtmlToMarkdown, Sites}

  defp convert(html, opts) do
    html
    |> Sites.preprocess(opts)
    |> HtmlToMarkdown.convert()
  end

  describe "applies?/1" do
    test "matches Substack hosts and the body-markup selector" do
      assert Sites.Substack.applies?(%{
               url: "https://patrikbaab.substack.com/p/a-bloody-delay-of-bankruptcy"
             })

      assert Sites.Substack.applies?(%{body_selector: ".body.markup"})
      refute Sites.Substack.applies?(%{url: "https://www.heise.de/news/foo"})
      refute Sites.Substack.applies?(%{body_selector: "article.akwa-article"})
    end
  end

  describe "tweet cards" do
    test "emits a Substack tweet card as a standalone status URL" do
      html = """
      <p>Merz made similar arrangements.[43]</p>
      <a href="https://x.com/jlrosing/status/2002193593503764743"
         data-component-name="Twitter2ToDOM"
         class="pencraft twitter-embed">
        <div data-attrs="{&quot;url&quot;:&quot;https://x.com/jlrosing/status/2002193593503764743&quot;,&quot;full_text&quot;:&quot;@ricwe123 Merz who was the European CEO in Blackrock&quot;,&quot;username&quot;:&quot;jlrosing&quot;,&quot;name&quot;:&quot;John Rosing&quot;}"
             class="twitter-embed">
          <img src="https://pbs.substack.com/profile_images/1620382619350310915/VZGJUj1D.jpg" alt="X avatar for @jlrosing">
          <span>John Rosing</span>
          <span>@jlrosing</span>
          <div>@ricwe123 Merz who was the European CEO in Blackrock made similar arrangements for Blackrock in Ukraine.</div>
          <a href="/photo/1">/photo/1</a>
        </div>
      </a>
      """

      md = convert(html, url: "https://patrikbaab.substack.com/p/a-bloody-delay-of-bankruptcy")

      assert md =~ "https://x.com/jlrosing/status/2002193593503764743"
      refute md =~ "X avatar for @jlrosing"
      refute md =~ "John Rosing"
      refute md =~ "European CEO"
      refute md =~ "/photo/1"
      refute md =~ "[https://x.com/jlrosing/status/2002193593503764743]"
    end

    test "puts the tweet URL on its own paragraph" do
      html = """
      <p>Before</p>
      <a href="https://twitter.com/CarmenDres91754/status/1870000000000000000" class="twitter-embed">
        <div>Tweet body that should not be concatenated</div>
      </a>
      <p>After</p>
      """

      md = convert(html, body_selector: ".body.markup")
      blocks = md |> String.split(~r/\n{2,}/) |> Enum.map(&String.trim/1)

      assert "Before" in blocks
      assert "https://twitter.com/CarmenDres91754/status/1870000000000000000" in blocks
      assert "After" in blocks
    end

    test "keeps a simple inline tweet citation as a markdown link" do
      html =
        ~s(<p>See <a href="https://x.com/jlrosing/status/2002193593503764743">this tweet</a>.</p>)

      md = convert(html, url: "https://patrikbaab.substack.com/p/x")

      assert md =~ "[this tweet](https://x.com/jlrosing/status/2002193593503764743)"
    end

    test "reads the status URL from Substack data-attrs on a tweet div" do
      html = """
      <div class="twitter-embed" data-attrs="{&quot;url&quot;:&quot;https://x.com/elgru5765/status/1871111111111111111&quot;,&quot;full_text&quot;:&quot;hello&quot;}">
        <span>hello</span>
      </div>
      """

      md = convert(html, url: "https://patrikbaab.substack.com/p/x")

      assert String.trim(md) == "https://x.com/elgru5765/status/1871111111111111111"
      refute md =~ "hello"
    end

    test "does not rewrite tweet cards for other sites" do
      html = """
      <a href="https://x.com/jlrosing/status/2002193593503764743" class="twitter-embed">
        <div>Merz who was the European CEO in Blackrock</div>
      </a>
      """

      md = convert(html, url: "https://www.heise.de/news/foo")

      assert md =~ "European CEO"
      refute md =~ ~r/^https:\/\/x\.com/m
    end
  end

  describe "footnotes" do
    test "converts Word endnote back-links and uses the visible number" do
      html = """
      <p>hegemony.<a href="https://forumgeopolitica.com/article/a-permanent-coup-detat-the-censorship-industry-part-ii#_edn26"><sup>[1]</sup></a></p>
      <p><a href="https://forumgeopolitica.com/article/a-permanent-coup-detat-the-censorship-industry-part-ii#_ednref26">[1]</a><span> Gramsci, Antonio: Gefängnishefte Bd. 3, Heft 5, Berlin1992, S. 659f.</span></p>
      """

      md = convert(html, url: "https://patrikbaab.substack.com/p/a-permanent-coup-detat-part-ii")

      assert md =~ "hegemony.[^1]"
      assert md =~ "[^1]: Gramsci, Antonio: Gefängnishefte"
      refute md =~ "[^26]"
      refute md =~ "[[1]]"
      refute md =~ "#_ednref26"
      refute md =~ "forumgeopolitica.com"
    end

    test "converts Word footnote back-links that still point at the original article" do
      html = """
      <p>hegemony.[1] They can affect international relations.</p>
      <p><a href="https://forumgeopolitica.com/article/from-sanctions-to-martial-law-and-a-state-of-emergency#_ftnref1">[1]</a><span> See the definition of censorship by Hofbauer, Hannes: Zensur. Vienna 2022, p. 7</span></p>
      """

      md = convert(html, url: "https://patrikbaab.substack.com/p/from-sanctions-to-martial-law-and")

      assert md =~ "[^1]: See the definition of censorship by Hofbauer"
      refute md =~ "[[1]]"
      refute md =~ "#_ftnref1"
      refute md =~ "forumgeopolitica.com"
    end

    test "converts Word footnote references and definitions on Substack" do
      html = """
      <p>for the financial investor.<a href="#_ftn43"><sup><span>[43]</span></sup></a></p>
      <p><a href="#_ftnref43"><sup><span>[43]</span></sup></a>Merz made similar arrangements.</p>
      """

      md = convert(html, url: "https://patrikbaab.substack.com/p/a-bloody-delay-of-bankruptcy")

      assert md =~ "investor.[^43]"
      assert md =~ "[^43]: Merz made similar arrangements."
      refute md =~ "#_ftn43"
      refute md =~ "#_ftnref43"
      refute md =~ "[[43]]"
    end

    test "keeps a footnote tweet URL on its own line after the definition marker" do
      html = """
      <p><a href="#_ftnref43"><sup><span>[43]</span></sup></a></p>
      <a href="https://x.com/jlrosing/status/2002193593503764743" class="twitter-embed">
        <div>Merz who was the European CEO in Blackrock</div>
      </a>
      """

      md = convert(html, body_selector: ".body.markup")

      assert md =~ "[^43]:"
      assert md =~ "https://x.com/jlrosing/status/2002193593503764743"
      refute md =~ "European CEO"
    end

    test "does not convert Word footnotes on other sites" do
      html = """
      <p>investor.<a href="#_ftn43"><sup><span>[43]</span></sup></a></p>
      """

      md = convert(html, url: "https://www.heise.de/news/foo")

      assert md =~ "[[43]](#_ftn43)"
      refute md =~ "[^43]"
    end
  end

  test "Composer applies Substack rules from the article URL" do
    html = """
    <div class="body markup">
      <p>investor.<a href="#_ftn43"><sup><span>[43]</span></sup></a></p>
    </div>
    """

    result =
      Composer.compose(html, %{
        body_selector: ".body.markup",
        url: "https://patrikbaab.substack.com/p/a-bloody-delay-of-bankruptcy",
        skip_classes: []
      })

    assert result.markdown =~ "investor.[^43]"
  end
end
