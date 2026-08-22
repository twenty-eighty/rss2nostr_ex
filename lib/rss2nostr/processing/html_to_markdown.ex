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

  alias Rss2Nostr.Processing.{ImageExtractor, Labels, Youtube}

  # Tracking parameters to remove from URLs
  @tracking_params ~w(
    _ dmcid fbclid fbc f_tid igshid originalReferrer ref_src
    utm_source utm_medium utm_campaign utm_term utm_content
    wt_zmc xing_share mc_cid mc_eid
  )

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
    Process.put({__MODULE__, :skip_classes}, normalize_skip_classes(skip))
    Process.put({__MODULE__, :conversion_rules}, rules)
    Process.put({__MODULE__, :language}, language)
    Process.put({__MODULE__, :soundcloud_permalink}, permalink)

    try do
      html
      |> preprocess_html()
      |> Floki.parse_document!()
      |> process_nodes()
      |> maybe_prepend_soundcloud(permalink)
      |> postprocess_markdown()
    after
      Process.delete({__MODULE__, :skip_classes})
      Process.delete({__MODULE__, :conversion_rules})
      Process.delete({__MODULE__, :language})
      Process.delete({__MODULE__, :soundcloud_permalink})
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
  def soundcloud_permalink(html) when is_binary(html) do
    hydration_permalink(html) ||
      List.first(track_permalinks_in_html(html)) ||
      player_inner_url(html)
  end

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
    text
    |> strip_summary_html()
    |> collapse_summary_whitespace()
    |> blank_to_nil()
  end

  def plain_summary(_), do: nil

  # Preprocess HTML before parsing
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
  defp process_nodes(nodes) when is_list(nodes) do
    nodes
    |> merge_adjacent_inline()
    |> Enum.map_join(&process_node/1)
  end

  defp process_nodes(node), do: process_node(node)

  defp process_node(text) when is_binary(text) do
    text
    |> String.replace(~r/\s+/u, " ")
  end

  defp process_node({tag, attrs, children}) do
    if skip_element?(attrs) do
      ""
    else
      process_tag(tag, attrs, children)
    end
  end

  defp process_node(_), do: ""

  defp process_tag(tag, attrs, children) do
    case tag do
      # Skip elements
      "script" -> ""
      "style" -> ""
      "nav" -> ""
      "header" -> ""
      "footer" -> ""
      "noscript" -> ""
      "button" -> ""
      "form" -> ""
      # Block elements
      "p" -> process_block("p", attrs, children)
      "div" -> process_block("div", attrs, children)
      "li" -> process_block("li", attrs, children)
      "section" -> process_block("section", attrs, children)
      # CommonMark hard break (two trailing spaces). A lone newline is
      # a space; `\` and `\n\n` show a backslash or a blank line.
      "br" -> "  \n"
      "hr" -> "\n\n---\n\n"
      # Headings
      "h1" -> "\n\n# #{process_nodes(children)}\n\n"
      "h2" -> "\n\n## #{process_nodes(children)}\n\n"
      "h3" -> "\n\n### #{process_nodes(children)}\n\n"
      "h4" -> "\n\n#### #{process_nodes(children)}\n\n"
      "h5" -> "\n\n##### #{process_nodes(children)}\n\n"
      "h6" -> "\n\n###### #{process_nodes(children)}\n\n"
      # Inline formatting
      "strong" -> wrap_inline(process_nodes(unwrap_same_role(children, :strong)), "**")
      "b" -> wrap_inline(process_nodes(unwrap_same_role(children, :strong)), "**")
      # Underscores so italic next to `**bold**` does not emit `***`,
      # which CommonMark treats as one delimiter run. Nested <em><i>
      # is the same role; wrapping twice emits `__text__` (bold).
      "em" ->
        if icon_class?(get_attr(attrs, "class", "")) do
          process_nodes(children)
        else
          wrap_inline(process_nodes(unwrap_same_role(children, :em)), "_")
        end

      "i" ->
        if icon_class?(get_attr(attrs, "class", "")) do
          process_nodes(children)
        else
          wrap_inline(process_nodes(unwrap_same_role(children, :em)), "_")
        end
      "u" -> wrap_inline(process_nodes(children), "_")
      "code" -> "`#{process_nodes(children)}`"
      "pre" -> "\n\n```\n#{Floki.text(children)}\n```\n\n"
      "mark" -> wrap_inline(process_nodes(children), "==")
      # Links
      "a" -> process_link(attrs, children)
      # Images
      "img" -> process_image(attrs)
      "figure" -> process_figure(attrs, children)
      "picture" -> process_picture(children)
      # Lists
      "ul" -> "\n\n#{process_list(children, :unordered)}\n\n"
      "ol" -> "\n\n#{process_list(children, :ordered)}\n\n"
      # Blockquote
      "blockquote" -> process_blockquote(children)
      # Table (simplified)
      "table" -> process_table(children)
      # Iframes (for embeds)
      "iframe" -> process_iframe(attrs)
      # Audio/Video
      "audio" -> process_audio(attrs, children)
      "video" -> process_video(attrs, children)
      # Inline elements - just process children
      "span" -> process_nodes(children)
      "article" -> process_nodes(children)
      "main" -> process_nodes(children)
      "aside" -> process_nodes(children)
      # Unknown - process children
      _ -> process_nodes(children)
    end
  end

  defp process_block(tag, attrs, children) do
    case matching_conversion({tag, attrs, children}) do
      %{action: "links_as_paragraphs"} ->
        Rss2Nostr.Processing.Conversion.links_as_paragraphs(children)

      _ ->
        case tag do
          "p" -> process_paragraph(children)
          "div" -> process_div(attrs, children)
          "li" -> process_nodes(children)
          _ -> process_nodes(children)
        end
    end
  end

  defp matching_conversion(node) do
    Enum.find(conversion_rules(), fn rule ->
      Rss2Nostr.Processing.Conversion.matches?(node, rule)
    end)
  end

  defp conversion_rules do
    Process.get({__MODULE__, :conversion_rules}, [])
  end

  # Adjacent <em>…</em><em>…</em> (or strong/b) would emit `*foo**bar*` /
  # `*foo****bar**`, which CommonMark does not treat as nested emphasis.
  defp merge_adjacent_inline(nodes) do
    Enum.reduce(nodes, [], &merge_next/2)
  end

  defp merge_next(node, acc) do
    last = List.last(acc)

    cond do
      same_inline_role?(last, node) ->
        List.replace_at(acc, -1, concat_inline(last, node))

      whitespace_only?(last) and length(acc) >= 2 and
          same_inline_role?(Enum.at(acc, -2), node) ->
        prev = Enum.at(acc, -2)
        Enum.drop(acc, -2) ++ [concat_inline(prev, last, node)]

      true ->
        acc ++ [node]
    end
  end

  defp concat_inline({tag, attrs, left}, {_, _, right}) do
    {tag, attrs, left ++ right}
  end

  defp concat_inline({tag, attrs, left}, ws, {_, _, right}) when is_binary(ws) do
    {tag, attrs, left ++ [ws] ++ right}
  end

  defp same_inline_role?({left, _, _}, {right, _, _}) do
    role = inline_role(left)
    role != nil and role == inline_role(right)
  end

  defp same_inline_role?(_, _), do: false

  defp inline_role(tag) when tag in ~w(em i), do: :em
  defp inline_role(tag) when tag in ~w(strong b), do: :strong
  defp inline_role(_), do: nil

  # WordPress often wraps a link as <em><i>…</i> </em>. Both tags are
  # italic; keep one marker pair so the space after the inner tag can
  # sit outside `_…_` instead of becoming `__…__and`.
  defp unwrap_same_role(children, role) do
    Enum.flat_map(children, fn
      {tag, attrs, inner} ->
        if inline_role(tag) == role do
          unwrap_same_role(inner, role)
        else
          [{tag, attrs, unwrap_same_role(inner, role)}]
        end

      other ->
        [other]
    end)
  end

  defp whitespace_only?(text) when is_binary(text), do: String.match?(text, ~r/\A\s*\z/u)
  defp whitespace_only?(_), do: false

  # CommonMark emphasis is invalid when a marker is next to whitespace
  # (`*foo *` is literal). Nested spans and pretty-printed HTML often leave
  # those spaces inside <em>/<strong>; move them outside the markers.
  defp wrap_inline(content, marker) do
    case Regex.run(~r/\A(\s*)(.*?)(\s*)\z/us, content) do
      [_, lead, mid, trail] when mid != "" ->
        lead <> marker <> mid <> marker <> trail

      [_, lead, _, trail] ->
        lead <> trail

      _ ->
        content
    end
  end

  defp process_paragraph(children) do
    content = process_nodes(children)

    if String.trim(content) == "*" do
      "\n\n---\n\n"
    else
      "\n\n#{content}\n\n"
    end
  end

  # Process div with special class handling
  defp process_div(attrs, children) do
    class = get_attr(attrs, "class", "")

    cond do
      String.contains?(class, "youtube") ->
        case process_youtube_div(attrs, children) do
          md when is_binary(md) and md != "" -> md
          _ -> process_nodes(children)
        end

      String.contains?(class, "powerpress") ->
        process_powerpress_div(children)

      String.contains?(String.downcase(class), "pullquote") ->
        process_blockquote(children)

      callout_div?(class) ->
        children
        |> blockify_callout_children()
        |> process_blockquote()

      social_bar_class?(class) ->
        process_social_bar(children)

      soundcloud_widget_div?(children) ->
        ""

      true ->
        process_nodes(children)
    end
  end

  defp social_bar_class?(class) when is_binary(class) do
    class
    |> String.downcase()
    |> String.split(~r/\s+/, trim: true)
    |> Enum.any?(fn token ->
      token in ~w(social-bar social-icons social-links social-media) or
        String.starts_with?(token, "social-")
    end)
  end

  defp process_social_bar(children) do
    links = collect_http_links(children)
    caption = social_bar_caption(children)

    markdown =
      case {links, caption} do
        {[%{href: href}], caption} when caption != "" ->
          markdown_media_link(caption, href, nil)

        {links, _} ->
          Enum.map_join(links, " · ", fn %{href: href, label: label} ->
            markdown_media_link(label, href, nil)
          end)
      end

    if String.trim(markdown) == "", do: "", else: "\n\n#{markdown}\n\n"
  end

  defp collect_http_links(nodes) do
    Enum.flat_map(List.wrap(nodes), fn
      {"a", attrs, inner} ->
        href = attrs |> get_attr("href") |> normalize_href()

        if is_binary(href) and http_url?(href) and not discard_link?(href) do
          [%{href: remove_tracking_params(href), label: link_fallback_label(attrs, inner, href)}]
        else
          []
        end

      {_, _, inner} ->
        collect_http_links(inner)

      _ ->
        []
    end)
  end

  defp social_bar_caption(nodes) do
    nodes
    |> List.wrap()
    |> Enum.flat_map(fn
      {"a", _, _} ->
        []

      {tag, _, inner} when tag in ~w(span p) ->
        text = inner |> Floki.text() |> String.trim()
        if text == "", do: [], else: [text]

      {_, _, inner} ->
        case social_bar_caption(inner) do
          "" -> []
          text -> [text]
        end

      text when is_binary(text) ->
        trimmed = String.trim(text)
        if trimmed == "", do: [], else: [trimmed]

      _ ->
        []
    end)
    |> Enum.join(" ")
    |> String.trim()
  end

  # Process links
  defp process_link(attrs, children) do
    href = attrs |> get_attr("href") |> normalize_href()

    cond do
      is_nil(href) or href == "" ->
        process_nodes(children) |> String.trim()

      relative_path?(href) ->
        ""

      discard_link?(href) ->
        ""

      soundcloud_widget_chrome?(href) ->
        ""

      true ->
        text = process_nodes(children) |> String.trim()
        clean_href = remove_tracking_params(href)
        label = if text == "", do: link_fallback_label(attrs, children, clean_href), else: text
        markdown_media_link(label, clean_href, get_attr(attrs, "title"))
    end
  end

  # Process images
  defp process_image(attrs) do
    src = get_best_image_src(attrs)
    alt = image_alt(attrs)

    if src && src != "" do
      "![#{alt}](#{src})"
    else
      ""
    end
  end

  # Prefer the largest usable srcset candidate, then data-src, then src.
  # Cloudinary/Substack URLs contain commas, so srcset must not be split on ",".
  defp get_best_image_src(attrs) do
    srcset = get_attr(attrs, "srcset") || get_attr(attrs, "data-srcset")

    [
      srcset && srcset != "" && get_largest_image(parse_srcset(srcset)),
      get_attr(attrs, "data-src"),
      get_attr(attrs, "src")
    ]
    |> Enum.find_value(fn
      url when is_binary(url) and url != "" ->
        cleaned = clean_image_url(url)
        if http_url?(cleaned), do: cleaned

      _ ->
        nil
    end)
  end

  # Parse srcset without breaking URLs that contain commas (Cloudinary transforms).
  defp parse_srcset(srcset) do
    width_matches = Regex.scan(~r/(\S+)\s+(\d+)w/i, srcset)

    candidates =
      if width_matches != [] do
        Enum.map(width_matches, fn [_, url, width] ->
          {url, String.to_integer(width)}
        end)
      else
        srcset
        |> String.split(~r/,\s+/)
        |> Enum.map(&parse_srcset_entry/1)
        |> Enum.reject(&is_nil/1)
      end

    Enum.filter(candidates, fn {url, _} -> usable_srcset_url?(url) end)
  rescue
    e ->
      Logger.debug("Failed to parse srcset: #{inspect(e)}")
      []
  end

  defp parse_srcset_entry(entry) do
    case String.split(String.trim(entry), ~r/\s+/, parts: 2) do
      [url, size] ->
        width =
          case Regex.run(~r/(\d+)/, size) do
            [_, digits] -> String.to_integer(digits)
            _ -> 0
          end

        {url, width}

      [url] when url != "" ->
        {url, 0}

      _ ->
        nil
    end
  end

  defp usable_srcset_url?(url) do
    String.starts_with?(url, ["http://", "https://", "//"])
  end

  defp get_largest_image([]), do: nil

  defp get_largest_image(images) do
    images
    |> Enum.max_by(fn {_url, width} -> width end)
    |> elem(0)
  end

  # Clean image URLs (CDN wrappers, encoded fetch targets, tracking params)
  defp clean_image_url(url) do
    url
    |> remove_wp_cdn_wrapper()
    |> ImageExtractor.display_url()
    |> remove_tracking_params()
  end

  defp http_url?(url) when is_binary(url) do
    uri = URI.parse(url)
    uri.scheme in ["http", "https"] and is_binary(uri.host) and uri.host != ""
  rescue
    _ -> false
  end

  defp http_url?(_), do: false

  defp remove_wp_cdn_wrapper(url) do
    # Remove i0.wp.com wrapper
    case Regex.run(~r/https?:\/\/i\d\.wp\.com\/(.+)/, url) do
      [_, inner_url] -> "https://#{inner_url}"
      _ -> url
    end
  end

  # Process figure with caption
  defp process_figure(_attrs, children) do
    # Find img and figcaption
    img = find_element(children, "img")
    figcaption = find_element(children, "figcaption")

    img_attrs =
      case img do
        {_, attrs, _} -> attrs
        _ -> []
      end

    src = get_best_image_src(img_attrs)
    alt = image_alt(img_attrs)
    caption = figcaption_text(figcaption)

    if src && src != "" do
      clean_src = clean_image_url(src)

      image_md =
        if caption != "" do
          "![#{alt}](#{clean_src} \"#{caption}\")"
        else
          "![#{alt}](#{clean_src})"
        end

      case figure_wrap_href(children, img_attrs, clean_src) do
        href when is_binary(href) -> "\n\n[#{image_md}](#{href})\n\n"
        _ -> "\n\n#{image_md}\n\n"
      end
    else
      # WordPress video embeds are <figure class="wp-block-embed-youtube">
      # wrapping a lazy iframe, with no <img>.
      process_nodes(children)
    end
  end

  # Substack Image2ToDOM wraps the <img> in <a>. Keep product/article
  # links; drop lightbox hrefs that only point at the same image.
  defp figure_wrap_href(children, img_attrs, image_src) do
    href =
      case find_element(children, "a") do
        {"a", attrs, _} -> get_attr(attrs, "href")
        _ -> nil
      end

    href = href || href_from_data_attrs(img_attrs)
    keep_figure_href(href, image_src)
  end

  defp href_from_data_attrs(attrs) do
    case get_attr(attrs, "data-attrs") do
      json when is_binary(json) and json != "" ->
        case Jason.decode(json) do
          {:ok, %{"href" => href}} when is_binary(href) and href != "" -> href
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp keep_figure_href(href, image_src) when is_binary(href) and href != "" do
    cond do
      relative_path?(href) or discard_link?(href) or not http_url?(href) ->
        nil

      same_image_ref?(href, image_src) or image_like_href?(href) ->
        nil

      true ->
        remove_tracking_params(href)
    end
  end

  defp keep_figure_href(_, _), do: nil

  defp same_image_ref?(left, right) do
    a = ImageExtractor.normalize_url(left)
    b = ImageExtractor.normalize_url(right)

    a != "" and b != "" and
      (a == b or Path.basename(a) == Path.basename(b))
  end

  defp image_like_href?(href) do
    path = href |> URI.parse() |> Map.get(:path, "") |> to_string() |> String.downcase()
    ext = path |> Path.extname() |> String.trim_leading(".")

    ext in ~w(jpg jpeg png gif webp heic heif svg avif) or
      String.contains?(path, "/image/fetch/")
  rescue
    _ -> false
  end

  # Bare `alt` (no value) is a boolean attribute; Floki yields "alt".
  defp image_alt(attrs) do
    case get_attr(attrs, "alt", "") do
      value when value in [nil, "", "alt"] -> ""
      value -> value
    end
  end

  defp figcaption_text(nil), do: ""

  defp figcaption_text(figcaption) do
    figcaption |> Floki.text() |> String.trim()
  end

  # Process picture element (get best source)
  defp process_picture(children) do
    # Try to find source with srcset, fallback to img
    source = find_element(children, "source")
    img = find_element(children, "img")

    attrs =
      case source do
        {_, attrs, _} ->
          attrs

        _ ->
          case img do
            {_, attrs, _} -> attrs
            _ -> []
          end
      end

    process_image(attrs)
  end

  # Process lists
  defp process_list(children, type, indent \\ 0) do
    children
    |> Enum.filter(fn
      {"li", _, _} -> true
      _ -> false
    end)
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {{"li", _, li_children}, index} ->
      prefix = String.duplicate("  ", indent)
      marker = if type == :ordered, do: "#{index}.", else: "-"
      content = process_nodes(li_children) |> String.trim()
      "#{prefix}#{marker} #{content}"
    end)
  end

  # Process blockquote
  defp process_blockquote(children) do
    content = process_nodes(children)

    quoted =
      content
      |> String.trim()
      |> String.split("\n")
      |> Enum.map(&("> " <> &1))
      |> collapse_blank_quote_lines()
      |> Enum.join("\n")

    "\n\n#{quoted}\n\n"
  end

  defp collapse_blank_quote_lines(lines) do
    {kept, _} =
      Enum.reduce(lines, {[], false}, fn line, {acc, skipping} ->
        blank? = String.trim(line) in [">", ""]

        cond do
          blank? and skipping ->
            {acc, true}

          true ->
            {acc ++ [line], blank?}
        end
      end)

    kept
  end

  defp callout_div?(class) when is_binary(class) do
    class
    |> String.downcase()
    |> String.split(~r/\s+/, trim: true)
    |> Enum.any?(&callout_class?/1)
  end

  defp callout_class?(token) do
    token in ~w(message notice alert callout infobox) or
      String.starts_with?(token, "message--") or
      String.starts_with?(token, "alert-") or
      String.starts_with?(token, "notice-")
  end

  # Spans and loose links in notice boxes are labels/actions, not inline text.
  defp blockify_callout_children(children) do
    Enum.flat_map(List.wrap(children), fn
      {"span", attrs, inner} ->
        [{"p", attrs, inner}]

      {"a", attrs, inner} ->
        [{"p", [], [{"a", attrs, inner}]}]

      text when is_binary(text) ->
        if String.trim(text) == "", do: [], else: [{"p", [], [text]}]

      other ->
        [other]
    end)
  end

  # Process table (simplified)
  defp process_table(children) do
    rows = find_all_elements(children, "tr")

    if Enum.empty?(rows) do
      ""
    else
      table_rows =
        rows
        |> Enum.map(fn {"tr", _, row_children} ->
          cells = find_all_elements(row_children, ["td", "th"])

          cells
          |> Enum.map_join(" | ", fn {_, _, cell_children} ->
            Floki.text(cell_children) |> String.trim()
          end)
          |> then(&"| #{&1} |")
        end)

      case table_rows do
        [header | rest] ->
          col_count = header |> String.split("|") |> length() |> Kernel.-(2)

          separator =
            "| " <> Enum.map_join(1..col_count, " | ", fn _ -> "---" end) <> " |"

          "\n\n#{header}\n#{separator}\n#{Enum.join(rest, "\n")}\n\n"

        _ ->
          ""
      end
    end
  end

  # Process iframe (YouTube, etc.)
  defp process_iframe(attrs) do
    src = iframe_src(attrs)

    cond do
      src == "" ->
        ""

      String.contains?(src, "youtube.com") || String.contains?(src, "youtu.be") ->
        youtube_markdown(src, get_attr(attrs, "title"))

      String.contains?(src, "podbean.com") ->
        process_podbean_iframe(src)

      String.contains?(src, "soundcloud.com") ->
        url =
          Process.get({__MODULE__, :soundcloud_permalink}) ||
            permalink_from_player(src) ||
            src

        soundcloud_listen_markdown(url)

      watch = embed_watch_url(src) ->
        "\n\n[#{watch_on(platform_label(watch))}](#{watch})\n\n"

      true ->
        ""
    end
  end

  @doc """
  Turns an embed iframe `src` into a watch-page URL when the host is known.
  YouTube is handled separately via `iframe_watch_url/1`.
  """
  @spec embed_watch_url(String.t() | nil) :: String.t() | nil
  def embed_watch_url(src) when is_binary(src) and src != "" do
    decoded = safe_decode_uri(src)
    uri = URI.parse(decoded)
    host = uri.host |> to_string() |> String.downcase()
    path = uri.path || ""

    cond do
      String.contains?(host, "odysee.com") ->
        odysee_watch_url(uri, path)

      String.contains?(host, "bitchute.com") ->
        bitchute_watch_url(uri, path)

      String.contains?(host, "rumble.com") ->
        rumble_watch_url(uri, path)

      String.contains?(host, "archive.org") ->
        archive_watch_url(uri, path)

      String.contains?(host, "rokfin.com") ->
        rokfin_watch_url(uri, path)

      true ->
        nil
    end
  rescue
    _ -> nil
  end

  def embed_watch_url(_), do: nil

  @doc """
  Watch-page URL for an iframe `src`, including YouTube.
  """
  @spec iframe_watch_url(String.t() | nil) :: String.t() | nil
  def iframe_watch_url(src) when is_binary(src) do
    cond do
      id = Youtube.video_id(src) -> "https://www.youtube.com/watch?v=#{id}"
      watch = embed_watch_url(src) -> watch
      true -> nil
    end
  end

  def iframe_watch_url(_), do: nil

  @doc """
  True when two URLs likely point at the same video (same host and
  video id / last path token). Used to drop WATCH ON links that
  duplicate an iframe already converted to a watch URL.
  """
  @spec same_video?(String.t() | nil, String.t() | nil) :: boolean()
  def same_video?(a, b) when is_binary(a) and is_binary(b) do
    case {video_key(a), video_key(b)} do
      {{host, id}, {host, id}} when is_binary(id) and id != "" -> true
      _ -> false
    end
  end

  def same_video?(_, _), do: false

  defp video_key(url) do
    watch = iframe_watch_url(url) || url
    uri = URI.parse(watch)
    host = normalize_video_host(uri.host)
    id = video_id_token(uri, watch)

    if host != "" and is_binary(id) and id != "", do: {host, id}, else: nil
  rescue
    _ -> nil
  end

  defp video_id_token(uri, url) do
    case Youtube.video_id(url) do
      id when is_binary(id) -> String.downcase(id)
      _ -> last_significant_token(uri)
    end
  end

  defp last_significant_token(uri) do
    (uri.path || "")
    |> String.split("/", trim: true)
    |> Enum.reject(&(String.downcase(&1) in ~w($ embed video details watch post v)))
    |> List.last()
    |> case do
      nil ->
        nil

      seg ->
        seg
        |> URI.decode()
        |> String.trim_leading("@")
        |> String.split(":")
        |> hd()
        |> String.downcase()
    end
  rescue
    _ -> nil
  end

  defp normalize_video_host(host) do
    host
    |> to_string()
    |> String.downcase()
    |> String.replace_prefix("www.", "")
    |> String.replace_prefix("old.", "")
    |> String.replace_prefix("m.", "")
  end

  defp odysee_watch_url(uri, path) do
    rest =
      cond do
        String.starts_with?(path, "/$/embed/") -> String.replace_prefix(path, "/$/embed/", "")
        String.starts_with?(path, "/embed/") -> String.replace_prefix(path, "/embed/", "")
        true -> nil
      end

    cond do
      is_binary(rest) and rest != "" ->
        uri_watch(uri, "/" <> rest)

      path not in [nil, "", "/"] ->
        uri_watch(uri, path)

      true ->
        nil
    end
  end

  defp bitchute_watch_url(uri, path) do
    case Regex.run(~r{/embed/([^/]+)/?}, path) do
      [_, id] -> uri_watch(uri, "/video/#{id}/")
      _ -> uri_watch(uri, path)
    end
  end

  defp rumble_watch_url(uri, path) do
    case Regex.run(~r{/embed/([^/]+)/?}, path) do
      [_, id] -> uri_watch(uri, "/embed/#{id}")
      _ -> uri_watch(uri, path)
    end
  end

  defp archive_watch_url(uri, path) do
    case Regex.run(~r{/embed/([^/]+)/?}, path) do
      [_, id] -> uri_watch(uri, "/details/#{id}")
      _ -> uri_watch(uri, path)
    end
  end

  defp rokfin_watch_url(uri, path) do
    case Regex.run(~r{/embed/(?:post/)?([^/]+)/?}, path) do
      [_, id] -> uri_watch(uri, "/post/#{id}")
      _ -> uri_watch(uri, path)
    end
  end

  defp uri_watch(uri, path) do
    URI.to_string(%{uri | path: path, query: nil, fragment: nil})
  end

  defp safe_decode_uri(url) do
    decoded = URI.decode(url)
    if decoded == url, do: url, else: safe_decode_uri(decoded)
  rescue
    _ -> url
  end

  defp platform_label(url) do
    host = url |> URI.parse() |> Map.get(:host) |> to_string() |> String.downcase()

    cond do
      String.contains?(host, "odysee.com") -> "Odysee"
      String.contains?(host, "bitchute.com") -> "Bitchute"
      String.contains?(host, "rumble.com") -> "Rumble"
      String.contains?(host, "archive.org") -> "Archive.org"
      String.contains?(host, "rokfin.com") -> "Rokfin"
      true -> "video"
    end
  rescue
    _ -> "video"
  end

  defp youtube_markdown(url, title) do
    case Youtube.video_id(url) do
      nil ->
        ""

      video_id ->
        text = Youtube.meaningful_title(title) || watch_on("YouTube")
        "\n\n[#{text}](https://www.youtube.com/watch?v=#{video_id})\n\n"
    end
  end

  # Pareto iframes www.podbean.com/ep/pb-{id} (LinkPreview.parsePodbeanUrl).
  # WordPress often lazy-loads the player as data-src with i={id}-pb.
  defp process_podbean_iframe(src) do
    case podbean_episode_url(src) do
      url when is_binary(url) ->
        "\n\n[#{listen_on("Podbean")}](#{url})\n\n"

      _ ->
        "\n\n[#{listen_on("Podbean")}](#{src})\n\n"
    end
  end

  defp podbean_episode_url(src) when is_binary(src) do
    decoded = unescape_attr(src)
    uri = URI.parse(decoded)
    query = uri.query || ""

    cond do
      id = podbean_player_id(query) ->
        "https://www.podbean.com/ep/pb-#{id}"

      id = podbean_path_id(uri.path) ->
        "https://www.podbean.com/ep/pb-#{id}"

      true ->
        nil
    end
  rescue
    _ -> nil
  end

  defp podbean_episode_url(_), do: nil

  defp podbean_player_id(query) do
    id =
      query
      |> URI.decode_query()
      |> Map.get("i")

    cond do
      is_binary(id) and id != "" -> String.replace_suffix(id, "-pb", "")
      true -> nil
    end
  end

  defp podbean_path_id(path) when is_binary(path) do
    case Regex.run(~r{(?:^|/)pb-([A-Za-z0-9]+-[A-Za-z0-9]+)(?:/|$)}, path) do
      [_, id] -> id
      _ -> nil
    end
  end

  defp podbean_path_id(_), do: nil

  defp iframe_src(attrs) do
    [get_attr(attrs, "src"), get_attr(attrs, "data-src")]
    |> Enum.find(&(is_binary(&1) and String.trim(&1) != ""))
    |> case do
      nil -> ""
      src -> unescape_attr(src)
    end
  end

  defp unescape_attr(value) when is_binary(value) do
    value
    |> String.replace("&amp;", "&")
    |> String.replace("&#038;", "&")
    |> String.replace("&#38;", "&")
  end

  defp unescape_attr(_), do: ""

  defp soundcloud_listen_markdown(url) when is_binary(url) and url != "" do
    "\n\n[#{listen_on("SoundCloud")}](#{url})\n\n"
  end

  defp soundcloud_listen_markdown(_), do: ""

  defp maybe_prepend_soundcloud(markdown, permalink) when is_binary(permalink) do
    if String.contains?(markdown, permalink) do
      markdown
    else
      "[#{listen_on("SoundCloud")}](#{permalink})\n\n" <> markdown
    end
  end

  defp maybe_prepend_soundcloud(markdown, _), do: markdown

  defp hydration_permalink(html) do
    case Regex.run(~r/window\.__sc_hydration\s*=\s*(\[.*?\])\s*;?/s, html) do
      [_, json] ->
        case Jason.decode(json) do
          {:ok, entries} when is_list(entries) ->
            Enum.find_value(entries, &hydration_sound_url/1)

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  defp hydration_sound_url(%{"hydratable" => "sound", "data" => %{"permalink_url" => url}})
       when is_binary(url) and url != "" do
    url
  end

  defp hydration_sound_url(_), do: nil

  defp track_permalinks_in_html(html) do
    ~r/https?:\/\/(?:www\.)?soundcloud\.com\/[^\s"'<>]+/i
    |> Regex.scan(html)
    |> List.flatten()
    |> Enum.map(&trim_url_punct/1)
    |> Enum.filter(&track_permalink?/1)
    |> Enum.uniq()
  end

  defp player_inner_url(html) do
    html
    |> soundcloud_player_srcs()
    |> Enum.find_value(&permalink_from_player/1)
  end

  defp soundcloud_player_srcs(html) do
    case Floki.parse_document(html) do
      {:ok, doc} ->
        doc
        |> Floki.find("iframe")
        |> Enum.flat_map(fn iframe ->
          [
            iframe |> Floki.attribute("src") |> List.first(),
            iframe |> Floki.attribute("data-src") |> List.first()
          ]
        end)
        |> Enum.filter(&(is_binary(&1) and String.contains?(&1, "w.soundcloud.com/player")))

      _ ->
        []
    end
  end

  defp permalink_from_player(src) when is_binary(src) do
    src = String.replace(src, "&amp;", "&")

    query =
      src
      |> URI.parse()
      |> Map.get(:query)
      |> to_string()
      |> URI.decode_query()

    case query["url"] do
      url when is_binary(url) and url != "" ->
        if soundcloud_host?(url), do: url

      _ ->
        nil
    end
  end

  defp permalink_from_player(_), do: nil

  defp track_permalink?(url) when is_binary(url) do
    uri = URI.parse(url)
    host = uri.host |> to_string() |> String.downcase()
    segments = (uri.path || "") |> String.split("/", trim: true)

    host in ["soundcloud.com", "www.soundcloud.com"] and
      length(segments) >= 2 and
      hd(segments) not in ~w(you pages discover stream search groups signin login)
  end

  defp track_permalink?(_), do: false

  defp soundcloud_host?(url) when is_binary(url) do
    host = url |> URI.parse() |> Map.get(:host) |> to_string() |> String.downcase()
    host == "soundcloud.com" or String.ends_with?(host, ".soundcloud.com")
  end

  defp soundcloud_host?(_), do: false

  defp soundcloud_widget_chrome?(href) do
    case Process.get({__MODULE__, :soundcloud_permalink}) do
      permalink when is_binary(permalink) ->
        soundcloud_host?(href) and
          (same_soundcloud_url?(href, permalink) or soundcloud_profile_of?(href, permalink))

      _ ->
        false
    end
  end

  defp soundcloud_widget_div?(children) do
    case Process.get({__MODULE__, :soundcloud_permalink}) do
      permalink when is_binary(permalink) ->
        anchors = collect_anchors(children)
        anchors != [] and Enum.all?(anchors, &soundcloud_widget_chrome?(get_attr(&1, "href")))

      _ ->
        false
    end
  end

  defp collect_anchors(nodes) when is_list(nodes), do: Enum.flat_map(nodes, &collect_anchors/1)
  defp collect_anchors({"a", attrs, _}), do: [attrs]
  defp collect_anchors({_, _, children}) when is_list(children), do: collect_anchors(children)
  defp collect_anchors(_), do: []

  defp same_soundcloud_url?(a, b) do
    normalize_soundcloud_url(a) == normalize_soundcloud_url(b)
  end

  defp soundcloud_profile_of?(href, permalink) do
    href_path =
      href |> URI.parse() |> Map.get(:path) |> to_string() |> String.split("/", trim: true)

    perm_path =
      permalink |> URI.parse() |> Map.get(:path) |> to_string() |> String.split("/", trim: true)

    case href_path do
      [user] -> match?([^user | _], perm_path)
      _ -> false
    end
  end

  defp normalize_soundcloud_url(url) do
    uri = URI.parse(url)
    host = uri.host |> to_string() |> String.downcase() |> String.replace_prefix("www.", "")
    path = uri.path |> to_string() |> String.trim_trailing("/")
    "https://#{host}#{path}"
  end

  defp trim_url_punct(url) do
    String.replace(url, ~r/[\.,;:)\]]+$/, "")
  end

  # Process YouTube div with data-attrs
  defp process_youtube_div(attrs, _children) do
    data_attrs = get_attr(attrs, "data-attrs", "")

    if data_attrs != "" do
      case Jason.decode(data_attrs) do
        {:ok, %{"videoId" => video_id} = data} ->
          text =
            Youtube.meaningful_title(data["title"] || data["videoTitle"]) || watch_on("YouTube")

          "\n\n[#{text}](https://www.youtube.com/watch?v=#{video_id})\n\n"

        _ ->
          ""
      end
    else
      ""
    end
  end

  # Process PowerPress audio player
  defp process_powerpress_div(children) do
    audio = find_element(children, "audio")

    src =
      case audio do
        {"audio", attrs, audio_children} ->
          get_attr(attrs, "src") || find_source_src(audio_children)

        _ ->
          nil
      end

    if src do
      clean_src = remove_tracking_params(src)
      "\n\n[#{audio_label()}](#{clean_src})\n\n"
    else
      ""
    end
  end

  defp find_source_src(children) do
    source = find_element(children, "source")

    case source do
      {"source", attrs, _} -> get_attr(attrs, "src")
      _ -> nil
    end
  end

  # Process audio element
  defp process_audio(attrs, children) do
    src = get_attr(attrs, "src") || find_source_src(children)

    if src do
      clean_src = remove_tracking_params(src)
      "\n\n[#{audio_label()}](#{clean_src})\n\n"
    else
      ""
    end
  end

  # Process video element
  defp process_video(attrs, children) do
    src = get_attr(attrs, "src") || find_source_src(children)

    if src do
      clean_src = remove_tracking_params(src)
      "\n\n[#{video_label()}](#{clean_src})\n\n"
    else
      ""
    end
  end

  # Remove tracking parameters from URL
  @spec remove_tracking_params(String.t() | any()) :: String.t()
  def remove_tracking_params(url) when is_binary(url) do
    uri = URI.parse(url)

    case uri.query do
      nil ->
        URI.to_string(uri)

      query when is_binary(query) ->
        cleaned_query =
          query
          |> URI.decode_query()
          |> Enum.reject(fn {key, _} ->
            Enum.any?(@tracking_params, &(String.downcase(key) == &1))
          end)
          |> URI.encode_query()

        new_query = if cleaned_query == "", do: nil, else: cleaned_query
        %{uri | query: new_query} |> URI.to_string()
    end
  rescue
    e ->
      Logger.debug("Failed to remove tracking params from URL: #{inspect(e)}")
      url
  end

  def remove_tracking_params(url), do: url

  # Postprocess markdown
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
    |> String.trim()
  end

  defp skip_element?(attrs) do
    classes =
      attrs
      |> get_attr("class", "")
      |> String.split(~r/\s+/, trim: true)

    classes != [] and Enum.any?(skip_classes(), &(&1 in classes))
  end

  defp skip_classes do
    Process.get({__MODULE__, :skip_classes}, @default_skip_classes)
  end

  defp normalize_skip_classes(classes) when is_list(classes) do
    classes
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_skip_classes(_), do: @default_skip_classes

  defp language do
    Process.get({__MODULE__, :language}, "en")
  end

  defp listen_on(platform), do: Labels.t(:listen_on, language(), platform: platform)
  defp watch_on(platform), do: Labels.t(:watch_on, language(), platform: platform)
  defp audio_label, do: Labels.t(:audio, language())
  defp video_label, do: Labels.t(:video, language())

  defp markdown_media_link(text, href, title) do
    if media_file_url?(href) and present_title?(title) do
      ~s|[#{text}](#{href} "#{escape_md_title(title)}")|
    else
      "[#{text}](#{href})"
    end
  end

  defp normalize_href(href) when is_binary(href) do
    case String.replace(href, ~r/\s+/, "") do
      "" -> nil
      url -> url
    end
  end

  defp normalize_href(_), do: nil

  defp link_fallback_label(attrs, children, href) do
    aria = get_attr(attrs, "aria-label")
    title = get_attr(attrs, "title")

    cond do
      present_title?(aria) -> String.trim(aria)
      present_title?(title) -> String.trim(title)
      label = icon_network_label(children) -> label
      label = host_network_label(href) -> label
      true -> href
    end
  end

  @fa_networks [
    {"telegram", "Telegram"},
    {"twitter", "Twitter"},
    {"x-twitter", "X"},
    {"facebook", "Facebook"},
    {"instagram", "Instagram"},
    {"youtube", "YouTube"},
    {"mastodon", "Mastodon"},
    {"whatsapp", "WhatsApp"},
    {"signal", "Signal"}
  ]

  defp icon_network_label(nodes) do
    classes = element_classes(nodes)

    Enum.find_value(@fa_networks, fn {name, label} ->
      if Enum.any?(classes, &(String.starts_with?(&1, "fa") and String.contains?(&1, name))) do
        label
      end
    end)
  end

  defp host_network_label(href) do
    host = href |> URI.parse() |> Map.get(:host) |> to_string() |> String.downcase()

    cond do
      host in ["t.me", "telegram.me", "www.telegram.me", "telegram.org"] -> "Telegram"
      String.ends_with?(host, ".t.me") -> "Telegram"
      true -> nil
    end
  rescue
    _ -> nil
  end

  defp element_classes(nodes) do
    Enum.flat_map(List.wrap(nodes), fn
      {_, attrs, inner} ->
        class_tokens(get_attr(attrs, "class", "")) ++ element_classes(inner)

      _ ->
        []
    end)
  end

  defp class_tokens(class) when is_binary(class) do
    class |> String.downcase() |> String.split(~r/\s+/, trim: true)
  end

  defp class_tokens(_), do: []

  defp icon_class?(class) do
    Enum.any?(class_tokens(class), fn token ->
      token in ~w(fa fab fas far fal fad icon dashicons material-icons) or
        String.starts_with?(token, "fa-") or
        String.starts_with?(token, "icon-")
    end)
  end

  defp media_file_url?(href) do
    ImageExtractor.audio_url?(href) or ImageExtractor.video_url?(href)
  end

  defp present_title?(title) when is_binary(title), do: String.trim(title) != ""
  defp present_title?(_), do: false

  defp escape_md_title(title) do
    String.replace(title, "\"", "'")
  end

  defp relative_path?(href) do
    String.starts_with?(href, "/") and not String.starts_with?(href, "//")
  end

  defp discard_link?(href) do
    uri = URI.parse(href)
    path = uri.path || ""

    String.ends_with?(path, "/subscribe") or
      String.ends_with?(path, "/comments") or
      share_action?(uri.query)
  rescue
    _ -> false
  end

  defp share_action?(nil), do: false

  defp share_action?(query) when is_binary(query) do
    query
    |> URI.decode_query()
    |> Map.get("action")
    |> Kernel.==("share")
  end

  # Helper: get attribute value
  defp get_attr(attrs, name, default \\ nil) do
    case List.keyfind(attrs, name, 0) do
      {_, value} -> value
      nil -> default
    end
  end

  # Helper: find first element by tag name, including nested children.
  defp find_element(nodes, tag) when is_list(nodes) do
    Enum.find_value(nodes, &find_element(&1, tag))
  end

  defp find_element({tag, _, _} = node, tag), do: node

  defp find_element({_, _, children}, tag) when is_list(children) do
    find_element(children, tag)
  end

  defp find_element(_, _), do: nil

  # Helper: find all elements by tag name(s)
  defp find_all_elements(nodes, tag) when is_binary(tag) do
    Enum.filter(nodes, fn
      {^tag, _, _} -> true
      _ -> false
    end)
  end

  defp find_all_elements(nodes, tags) when is_list(tags) do
    Enum.filter(nodes, fn
      {tag, _, _} -> tag in tags
      _ -> false
    end)
  end

  defp strip_summary_html(text) do
    if html_fragment?(text) do
      case parse_summary_html(text) do
        {:ok, nodes} ->
          nodes
          |> filter_summary_nodes()
          |> Floki.text(sep: " ")

        _ ->
          text
      end
    else
      text
    end
  end

  defp parse_summary_html(text) do
    case Floki.parse_fragment(text) do
      {:ok, nodes} -> {:ok, nodes}
      _ -> Floki.parse_document(text)
    end
  end

  defp html_fragment?(text) do
    String.contains?(text, "<") and Regex.match?(~r/<\/?[a-zA-Z]/, text)
  end

  defp filter_summary_nodes(nodes) when is_list(nodes) do
    Enum.flat_map(nodes, &filter_summary_node/1)
  end

  defp filter_summary_node(node) do
    case node do
      {tag, _, _} when tag in ["iframe", "script", "style", "noscript"] ->
        []

      {tag, attrs, children} ->
        if summary_chrome_node?({tag, attrs, children}) do
          []
        else
          [{tag, attrs, filter_summary_nodes(children)}]
        end

      other ->
        [other]
    end
  end

  defp summary_chrome_node?({tag, attrs, children}) do
    style = attrs |> get_attr("style", "") |> String.downcase()
    hrefs = collect_hrefs(children)
    soundcloud_links? = hrefs != [] and Enum.all?(hrefs, &soundcloud_host?/1)

    cond do
      not soundcloud_links? ->
        false

      String.contains?(style, "font-size: 10px") or String.contains?(style, "font-size:10px") ->
        true

      tag in ["div", "span"] and not has_paragraph?(children) and chrome_only_text?(children) ->
        true

      true ->
        false
    end
  end

  defp chrome_only_text?(children) do
    text =
      children
      |> Floki.text()
      |> String.replace("·", " ")
      |> String.replace(~r/\s+/u, " ")
      |> String.trim()

    labels =
      children
      |> collect_anchor_nodes()
      |> Enum.map(&Floki.text/1)
      |> Enum.join(" ")
      |> String.replace(~r/\s+/u, " ")
      |> String.trim()

    text == "" or text == labels
  end

  defp collect_hrefs(nodes) do
    nodes
    |> collect_anchor_nodes()
    |> Enum.map(fn {"a", attrs, _} -> get_attr(attrs, "href") end)
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
  end

  defp collect_anchor_nodes(nodes) when is_list(nodes),
    do: Enum.flat_map(nodes, &collect_anchor_nodes/1)

  defp collect_anchor_nodes({"a", _, _} = node), do: [node]

  defp collect_anchor_nodes({_, _, children}) when is_list(children),
    do: collect_anchor_nodes(children)

  defp collect_anchor_nodes(_), do: []

  defp has_paragraph?(nodes) when is_list(nodes) do
    Enum.any?(nodes, fn
      {"p", _, children} -> String.trim(Floki.text(children)) != ""
      {_, _, children} -> has_paragraph?(children)
      _ -> false
    end)
  end

  defp has_paragraph?(_), do: false

  defp collapse_summary_whitespace(text) do
    text
    |> String.replace(~r/[\r\n]+/, " ")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
