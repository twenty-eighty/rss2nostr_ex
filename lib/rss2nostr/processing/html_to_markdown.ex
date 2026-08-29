defmodule Rss2Nostr.Processing.HtmlToMarkdown do
  @moduledoc """
  Converts HTML to Markdown with special handling for:
  - Tracking parameter removal from URLs
  - YouTube, Odysee, Bitchute, Rumble, Archive.org, SoundCloud, Podbean embeds
  - Responsive images (srcset handling)
  - Figures with captions

  Site-specific rewrites (Substack tweet cards, Corbett WATCH ON rows)
  live in `Rss2Nostr.Processing.Sites` and run before this converter.
  """

  require Logger

  alias Rss2Nostr.Processing.Labels

  alias Rss2Nostr.Processing.HtmlToMarkdown.{
    Blocks,
    Dom,
    Embeds,
    EmbedUrls,
    Images,
    Inline,
    LinkTags,
    Links,
    SoundcloudPermalink,
    Summary,
    Tables,
    TrackingParams
  }

  @default_skip_classes ~w(
    OUTBRAIN article-disclaimer ad-label pre-akwa-toc__list
    et_pb_post_title et_pb_comments_0_tb_body
    beitraganriss lead powerpress_links powerpress_links_mp3
    shariff subscription-widget-wrap subscription-widget subscribe-widget
    header-anchor-parent post-header post-ufi
  )

  @doc """
  CSS classes dropped during conversion (ads, comments, teaser blocks).
  """
  @spec default_skip_classes() :: [String.t()]
  def default_skip_classes, do: @default_skip_classes

  @doc """
  Converts HTML to Markdown.

  Options:
    * `:skip_classes` — class name fragments to drop. Defaults to
      `default_skip_classes/0`. Pass `[]` to keep every class.
    * `:conversion_rules` — visual XPath rules. Only matching elements
      are rewritten (for example, one Markdown line per link).
    * `:language` — ISO 639-1 feed language for generated labels
      (`Listen on SoundCloud`, `Watch on YouTube`, …). Defaults to English.
  """
  @spec convert(String.t() | nil, keyword()) :: String.t() | nil
  def convert(html, opts \\ [])
  def convert(nil, _opts), do: nil
  def convert("", _opts), do: nil

  def convert(html, opts) when is_binary(html) do
    skip = Keyword.get(opts, :skip_classes, @default_skip_classes)
    rules = Keyword.get(opts, :conversion_rules, [])
    language = Labels.normalize(Keyword.get(opts, :language))
    permalink = soundcloud_permalink(html)
    color = SoundcloudPermalink.player_color(html)

    Process.put({__MODULE__, :skip_classes}, normalize_skip_classes(skip))
    Process.put({__MODULE__, :conversion_rules}, rules)
    Process.put({__MODULE__, :language}, language)
    Process.put({__MODULE__, :soundcloud_permalink}, permalink)
    Process.put({__MODULE__, :soundcloud_color}, color)

    try do
      html
      |> preprocess_html()
      |> Floki.parse_document!()
      |> process_nodes()
      |> Embeds.maybe_prepend_soundcloud(permalink)
      |> postprocess_markdown()
    after
      Process.delete({__MODULE__, :skip_classes})
      Process.delete({__MODULE__, :conversion_rules})
      Process.delete({__MODULE__, :language})
      Process.delete({__MODULE__, :soundcloud_permalink})
      Process.delete({__MODULE__, :soundcloud_color})
    end
  rescue
    e ->
      Logger.warning("HTML to Markdown conversion failed: #{inspect(e)}")
      # Fallback: strip HTML tags
      html |> Floki.parse_document!() |> Floki.text()
  end

  @doc """
  SoundCloud track permalink from raw HTML.

  Scripts are stripped before conversion, so this runs on the original
  markup. Prefers `__sc_hydration` `permalink_url`, then a
  `soundcloud.com/user/track` page URL, then the player iframe `url`
  query (often `api.soundcloud.com/tracks/...`).
  """
  @spec soundcloud_permalink(String.t()) :: String.t() | nil
  def soundcloud_permalink(html) when is_binary(html), do: SoundcloudPermalink.permalink(html)
  def soundcloud_permalink(_), do: nil

  @doc """
  Plain-text teaser for a NIP-23 summary tag.

  RSS `<description>` often includes HTML (iframes, SoundCloud widget
  chrome). Tags are stripped, embeds dropped, and whitespace collapsed
  like the PHP importer's `stripHtml`.
  """
  @spec plain_summary(String.t() | nil) :: String.t() | nil
  def plain_summary(nil), do: nil
  def plain_summary(""), do: nil

  def plain_summary(text) when is_binary(text) do
    Summary.to_plain(text) |> blank_to_nil()
  end

  def plain_summary(_), do: nil

  # Preprocess HTML before parsing
  @spec preprocess_html(String.t()) :: String.t()
  defp preprocess_html(html) do
    html
    |> String.replace(~r/<script[^>]*>.*?<\/script>/is, "")
    |> String.replace(~r/<style[^>]*>.*?<\/style>/is, "")
    |> String.replace(~r/<!--.*?-->/s, "")
    |> preserve_inline_spaces()
  end

  # Floki drops ordinary spaces between inline tags and inside
  # `<span> </span>`. Keep them as `&nbsp;` so a real word space is
  # not lost, while a split word like `<em>V</em><em>ideo</em>` stays
  # glued. That includes a space before a closing parent
  # (`</i> </em>and`), which would otherwise glue the next word.
  #
  # Call this before any Floki.parse + raw_html round-trip (body
  # extract, site preprocess). Those run before convert/2 and would
  # otherwise drop the space first.
  @inline_tags "em|i|strong|b|span|a|code|mark"

  @spec preserve_inline_spaces(String.t()) :: String.t()
  def preserve_inline_spaces(html) when is_binary(html) do
    html
    |> String.replace(
      ~r/(<\/(?:#{@inline_tags})>)(\s+)(<\/?(?:#{@inline_tags})(?:\s[^>]*)?>)/i,
      "\\1&nbsp;\\3"
    )
    |> String.replace(
      ~r/(<span(?:\s[^>]*)?>)(\s+)(<\/span>)/i,
      "\\1&nbsp;\\3"
    )
  end

  def preserve_inline_spaces(html), do: html

  # Process DOM nodes to Markdown
  @spec process_nodes(Floki.html_tree() | Floki.html_node()) :: String.t()
  defp process_nodes(nodes) when is_list(nodes) do
    nodes
    |> Inline.merge_adjacent()
    |> Enum.map_join(&process_node/1)
  end

  defp process_nodes(node), do: process_node(node)

  @spec process_node(Floki.html_tree() | Floki.html_node()) :: String.t()
  defp process_node(text) when is_binary(text) do
    collapsed = String.replace(text, ~r/\s+/u, " ")

    if Process.get({__MODULE__, :in_link}) do
      collapsed
    else
      Links.autolink_platform_urls(collapsed)
    end
  end

  defp process_node({tag, attrs, children}) do
    if skip_element?(attrs) do
      ""
    else
      process_tag(tag, attrs, children)
    end
  end

  defp process_node(_), do: ""

  @spec process_tag(String.t(), [{String.t(), String.t()}], [Floki.html_node()]) :: String.t()
  defp process_tag(tag, attrs, children) do
    cond do
      skipped_tag?(tag) ->
        ""

      heading_tag?(tag) ->
        process_heading_tag(tag, children)

      emphasis_tag?(tag) ->
        process_emphasis_tag(tag, attrs, children)

      tag in ~w(a img figure picture ul ol blockquote table iframe audio video) ->
        process_media_tag(tag, attrs, children)

      tag in ~w(p div li section) ->
        process_block(tag, attrs, children)

      tag == "br" ->
        "  \n"

      tag == "hr" ->
        "\n\n---\n\n"

      tag in ~w(span article main aside) ->
        process_nodes(children)

      true ->
        process_nodes(children)
    end
  end

  @spec skipped_tag?(String.t()) :: boolean()
  defp skipped_tag?(tag), do: tag in ~w(script style nav header footer noscript button form)

  @spec heading_tag?(String.t()) :: boolean()
  defp heading_tag?(tag), do: tag in ~w(h1 h2 h3 h4 h5 h6)

  @spec emphasis_tag?(String.t()) :: boolean()
  defp emphasis_tag?(tag),
    do: tag in ~w(strong b em i u code pre mark)

  @spec process_heading_tag(String.t(), [Floki.html_node()]) :: String.t()
  defp process_heading_tag(tag, children),
    do: Inline.process_heading(tag, children, &process_nodes/1)

  @spec process_emphasis_tag(String.t(), [{String.t(), String.t()}], [Floki.html_node()]) :: String.t()
  defp process_emphasis_tag(tag, attrs, children),
    do: Inline.process_emphasis(tag, attrs, children, &process_nodes/1)

  @spec process_media_tag(String.t(), [{String.t(), String.t()}], [Floki.html_node()]) :: String.t()
  defp process_media_tag("a", attrs, children),
    do: LinkTags.process_link(attrs, children, &process_nodes/1)

  defp process_media_tag("img", attrs, _), do: Images.process_image(attrs)

  defp process_media_tag("figure", attrs, children),
    do: Images.process_figure(attrs, children, &process_nodes/1)

  defp process_media_tag("picture", _attrs, children), do: Images.process_picture(children)

  defp process_media_tag("ul", _attrs, children),
    do: "\n\n#{Blocks.process_list(children, :unordered, &process_nodes/1)}\n\n"

  defp process_media_tag("ol", _attrs, children),
    do: "\n\n#{Blocks.process_list(children, :ordered, &process_nodes/1)}\n\n"

  defp process_media_tag("blockquote", _attrs, children),
    do: Blocks.process_blockquote(children, &process_nodes/1)

  defp process_media_tag("table", _attrs, children), do: Tables.process(children)
  defp process_media_tag("iframe", attrs, _), do: Embeds.process_iframe(attrs)
  defp process_media_tag("audio", attrs, children), do: Embeds.process_audio(attrs, children)
  defp process_media_tag("video", attrs, children), do: Embeds.process_video(attrs, children)

  @spec process_block(String.t(), [{String.t(), String.t()}], [Floki.html_node()]) :: String.t()
  defp process_block(tag, attrs, children) do
    case matching_conversion({tag, attrs, children}) do
      %{action: "links_as_paragraphs"} ->
        Rss2Nostr.Processing.Conversion.links_as_paragraphs(children)

      _ ->
        case tag do
          "p" -> Blocks.process_paragraph(children, &process_nodes/1)
          "div" -> Blocks.process_div(attrs, children, &process_nodes/1)
          "li" -> process_nodes(children)
          _ -> process_nodes(children)
        end
    end
  end

  @spec matching_conversion(Floki.html_node()) :: Rss2Nostr.Processing.Conversion.rule() | nil
  defp matching_conversion(node) do
    Enum.find(conversion_rules(), fn rule ->
      Rss2Nostr.Processing.Conversion.matches?(node, rule)
    end)
  end

  @spec conversion_rules() :: [Rss2Nostr.Processing.Conversion.rule()]
  defp conversion_rules do
    Process.get({__MODULE__, :conversion_rules}, [])
  end

  @doc """
  Turns an embed iframe `src` into a watch-page URL when the host is known.
  YouTube is handled separately via `iframe_watch_url/1`.
  """
  @spec embed_watch_url(String.t() | nil) :: String.t() | nil
  def embed_watch_url(src), do: EmbedUrls.embed_watch_url(src)

  @doc """
  Watch-page URL for an iframe `src`, including YouTube.
  """
  @spec iframe_watch_url(String.t() | nil) :: String.t() | nil
  def iframe_watch_url(src), do: EmbedUrls.iframe_watch_url(src)

  @doc """
  True when two URLs likely point at the same video (same host and
  video id / last path token).
  """
  @spec same_video?(String.t() | nil, String.t() | nil) :: boolean()
  def same_video?(a, b), do: EmbedUrls.same_video?(a, b)

  @spec remove_tracking_params(String.t() | nil) :: String.t()
  def remove_tracking_params(url), do: TrackingParams.remove(url)

  # Postprocess markdown
  @spec postprocess_markdown(String.t()) :: String.t()
  defp postprocess_markdown(markdown) do
    markdown
    # Max 2 newlines
    |> String.replace(~r/\n{3,}/, "\n\n")
    # Trailing tab or a single space. Keep two spaces — that is a
    # CommonMark hard break from <br>.
    |> String.replace(~r/\t+\n/, "\n")
    |> String.replace(~r/(?<! ) \n/, "\n")
    # Lines with only whitespace
    |> String.replace(~r/\n[ \t]+\n/, "\n\n")
    |> String.replace(~r/\[\^([^\]]+)\]:[ \t]+/, "[^\\1]: ")
    # Word/Substack footnotes that are only a marker often leave the
    # body (a tweet URL, a link) on the next paragraph. Most Markdown
    # renderers treat that as a separate block, so the footnote looks
    # empty. Pull the first following content line onto `[^n]:`.
    |> pull_up_empty_footnote_bodies()
    |> String.trim()
  end

  @spec pull_up_empty_footnote_bodies(String.t()) :: String.t()
  defp pull_up_empty_footnote_bodies(markdown) do
    Regex.replace(
      ~r/^(\[\^[^\]]+\]:)[ \t]*\n+(?=[^\s\n])/m,
      markdown,
      "\\1 "
    )
  end

  @spec skip_element?([{String.t(), String.t()}]) :: boolean()
  defp skip_element?(attrs) do
    Images.tracking_wrapper?(attrs) or skip_class?(attrs)
  end

  @spec skip_class?([{String.t(), String.t()}]) :: boolean()
  defp skip_class?(attrs) do
    classes =
      attrs
      |> get_attr("class", "")
      |> String.split(~r/\s+/, trim: true)

    classes != [] and Enum.any?(skip_classes(), &(&1 in classes))
  end

  @spec skip_classes() :: [String.t()]
  defp skip_classes do
    Process.get({__MODULE__, :skip_classes}, @default_skip_classes)
  end

  @spec normalize_skip_classes(String.t() | [String.t()] | nil) :: [String.t()]
  defp normalize_skip_classes(classes) when is_list(classes) do
    classes
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_skip_classes(_), do: @default_skip_classes

  @spec get_attr([{String.t(), String.t()}], String.t(), String.t() | nil) :: String.t() | nil
  defp get_attr(attrs, name, default), do: Dom.get_attr(attrs, name, default)

  @spec blank_to_nil(String.t()) :: String.t() | nil
  defp blank_to_nil(""), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
