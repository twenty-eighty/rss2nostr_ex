defmodule Rss2Nostr.Processing.BodySchema do
  @moduledoc """
  Picks an article-body region without requiring CSS knowledge.

  Known site URL patterns can preselect a schema. Matching page-builder
  markup (WPBakery, Elementor, Divi, …) is always offered. Other pages
  use semantic tags, schema.org, common content classes, and discovered
  wrappers; the tightest substantial region is recommended.
  """

  alias Rss2Nostr.Processing.{Conversion, HtmlToMarkdown}

  @url_schemas [
    {~r/(^|\.)substack\.com$/i, ".body.markup", "Substack article"},
    {~r/(^|\.)heise\.de$/i, "article.akwa-article", "Heise article"},
    {~r/(^|\.)corbettreport\.com$/i, "div.et_pb_column_0_tb_body", "Corbett article"},
    {~r/(^|\.)manova\.news$/i, "div.article-content", "Manova article"},
    {~r/(^|\.)multipolar-magazin\.de$/i, "div.blog-list-content", "Multipolar article"},
    {~r/(^|\.)freie-medienakademie\.de$/i, ".medienplus-article", "Freie Medienakademie article"}
  ]

  # Tightest-first. Tiny sibling chrome is dropped at extract time.
  @page_builders [
    {".vc_column-inner > .wpb_wrapper", "WPBakery column"},
    {"div.wpb_wrapper", "WPBakery wrapper"},
    {"div.wpb_text_column", "WPBakery text"},
    {".elementor-widget-theme-post-content", "Elementor post content"},
    {".et_pb_post_content", "Divi post content"},
    {".fl-post-content", "Beaver Builder post"},
    {".wp-block-post-content", "Gutenberg post content"}
  ]

  @preset_labels Map.merge(
                   %{
                     "div.entry-content" => "WordPress article",
                     "article.akwa-article" => "Heise article",
                     "article" => "HTML article element",
                     "div.et_pb_column_0_tb_body" => "Corbett article",
                     "div.article-content" => "Manova article",
                     "div.blog-list-content" => "Multipolar article",
                     ".medienplus-article" => "Freie Medienakademie article",
                     ".body.markup" => "Substack article",
                     ".post-content" => "Blog post content",
                     ".post_content" => "Blog post content",
                     "[itemprop='articleBody']" => "Article body",
                     "main" => "HTML main element"
                   },
                   Map.new(@page_builders)
                 )

  @page_builder_selectors Enum.map(@page_builders, &elem(&1, 0))

  # Prefer these over discovered wrappers (sidebars, tabs, #content, …).
  @article_selectors [
    "div.entry-content",
    ".wp-block-post-content",
    ".post-content",
    ".post_content",
    "[itemprop='articleBody']",
    "div.article-content",
    "article"
  ]

  @skip_classes MapSet.new(~w(
    row col column columns container grid flex
    inner outer wrap wrapper
    clearfix hidden visible active open
  ))

  @skip_discover_class ~r/(^|[-_])(tab|tabs|sidebar|related|comment|comments|comm|widget|menu|nav|footer|header|share|social|popular|breadcrumb|pagination)s?([-_]|$)/i

  @type schema :: %{selector: String.t(), label: String.t()}
  @type region :: %{
          selector: String.t(),
          label: String.t(),
          first_line: String.t(),
          word_count: non_neg_integer(),
          recommended: boolean(),
          selected: boolean()
        }

  @spec schema_for_url(String.t() | nil) :: schema() | nil
  def schema_for_url(url) when is_binary(url) do
    host = url |> URI.parse() |> Map.get(:host) |> to_string()

    Enum.find_value(@url_schemas, fn {pattern, selector, label} ->
      if Regex.match?(pattern, host) do
        %{selector: selector, label: label}
      end
    end)
  rescue
    _ -> nil
  end

  def schema_for_url(_), do: nil

  @spec selector_for_url(String.t() | nil) :: String.t() | nil
  def selector_for_url(url) do
    case schema_for_url(url) do
      %{selector: selector} -> selector
      _ -> nil
    end
  end

  @doc """
  Selector to use when the source has none stored: a known URL schema
  if it matches, otherwise the tightest substantial region in `html`.
  """
  @spec preferred_selector(String.t() | nil, String.t() | nil) :: String.t() | nil
  def preferred_selector(html, url) do
    case candidates(html, url: url) do
      [] ->
        nil

      regions ->
        recommended_selector(regions)
    end
  end

  @doc """
  True when `selector` is a known site preset (Substack, Corbett, WordPress, …).
  """
  @spec known_selector?(String.t() | nil) :: boolean()
  def known_selector?(selector) when is_binary(selector) do
    selector = String.trim(selector)
    selector != "" and Map.has_key?(@preset_labels, selector)
  end

  def known_selector?(_), do: false

  @spec known_selectors() :: [String.t()]
  def known_selectors, do: Map.keys(@preset_labels)

  @spec matches?(String.t(), String.t()) :: boolean()
  def matches?(html, selector) when is_binary(html) and is_binary(selector) and selector != "" do
    case Floki.parse_document(html) do
      {:ok, doc} -> Floki.find(doc, selector) != []
      _ -> false
    end
  rescue
    _ -> false
  end

  def matches?(_, _), do: false

  @spec candidates(String.t() | nil, keyword()) :: [region()]
  def candidates(html, opts \\ [])
  def candidates(html, _opts) when html in [nil, ""], do: []

  def candidates(html, opts) do
    url = Keyword.get(opts, :url)
    selected = Keyword.get(opts, :selected)
    schema = schema_for_url(url)
    page = region(html, "", "Whole page", schema)

    preset_regions =
      @preset_labels
      |> Enum.filter(fn {selector, _} -> matches?(html, selector) end)
      |> Enum.map(fn {selector, label} ->
        region(html, selector, label, schema)
      end)

    discovered_regions =
      html
      |> discovered_selectors()
      |> Enum.map(fn selector -> region(html, selector, label_for(selector), schema) end)
      |> Enum.filter(&(&1.word_count > 0 and &1.word_count < page.word_count))

    regions =
      ([page | preset_regions] ++ discovered_regions)
      |> Enum.reject(&(&1.selector != "" and &1.word_count == 0))
      |> prefer_distinct_regions()
      |> mark_recommended(schema)

    chosen = selected || recommended_selector(regions) || ""

    regions
    |> keep_visible(chosen)
    |> Enum.sort_by(&{!&1.recommended, -&1.word_count})
    |> mark_selected(chosen)
  end

  @doc """
  HTML for `selector`, keeping only outermost matches that still look
  like article body (drops nested duplicates and tiny sibling chrome).
  """
  @spec extract(String.t() | nil, String.t() | nil) :: String.t() | nil
  def extract(html, selector)
  def extract(html, _selector) when html in [nil, ""], do: nil
  def extract(_html, selector) when selector in [nil, ""], do: nil

  def extract(html, selector) when is_binary(html) and is_binary(selector) do
    html = HtmlToMarkdown.preserve_inline_spaces(html)

    case Floki.parse_document(html) do
      {:ok, doc} ->
        case doc |> Floki.find(selector) |> drop_nested() |> keep_substantial() do
          [] -> nil
          found -> Floki.raw_html(found)
        end

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  @spec start_blocks(String.t() | nil, keyword()) :: [map()]
  def start_blocks(html, opts \\ [])
  def start_blocks(html, _opts) when html in [nil, ""], do: []

  def start_blocks(html, opts) do
    limit = Keyword.get(opts, :limit, 20)
    selected = Keyword.get(opts, :selected)

    case Floki.parse_document(html) do
      {:ok, doc} ->
        doc
        |> Floki.find("p, h1, h2, h3, h4, h5, h6")
        |> Enum.flat_map(&block_from_node/1)
        |> Enum.take(limit)
        |> Enum.map(fn block ->
          Map.put(block, :selected, block.xpath == selected)
        end)

      _ ->
        []
    end
  rescue
    _ -> []
  end

  @spec apply_start_at(String.t() | nil, String.t() | nil) :: String.t() | nil
  def apply_start_at(html, start_at) when html in [nil, ""] or start_at in [nil, ""], do: html

  def apply_start_at(html, start_at) when is_binary(html) and is_binary(start_at) do
    html = HtmlToMarkdown.preserve_inline_spaces(html)

    case Floki.parse_document(html) do
      {:ok, doc} ->
        case drop_before(content_children(doc), start_at) do
          {:ok, children} -> Floki.raw_html(children)
          :miss -> html
        end

      _ ->
        html
    end
  rescue
    _ -> html
  end

  defp discovered_selectors(html) do
    case Floki.parse_document(html) do
      {:ok, doc} ->
        doc
        |> Floki.find("article, main, section, div")
        |> Enum.flat_map(&node_selectors/1)
        |> Enum.uniq()
        |> Enum.reject(&Map.has_key?(@preset_labels, &1))

      _ ->
        []
    end
  rescue
    _ -> []
  end

  defp node_selectors({tag, attrs, _}) when is_binary(tag) do
    classes =
      attrs
      |> attr("class")
      |> String.split(~r/\s+/, trim: true)
      |> Enum.filter(&usable_class?/1)
      |> Enum.map(&"#{tag}.#{&1}")

    itemprop =
      case attr(attrs, "itemprop") do
        "articleBody" -> ["[itemprop='articleBody']"]
        _ -> []
      end

    id =
      case attr(attrs, "id") do
        id when id in ["content", "main", "main-content", "article", "post", "primary"] ->
          ["##{id}"]

        _ ->
          []
      end

    itemprop ++ id ++ classes
  end

  defp node_selectors(_), do: []

  @discover_class ~r/content|article|entry|post|body|markup|wpb_|elementor|et_pb|fl-|wp-block/i

  defp usable_class?(class) do
    String.match?(class, ~r/^[A-Za-z][A-Za-z0-9_-]{3,}$/) and
      not MapSet.member?(@skip_classes, String.downcase(class)) and
      not String.match?(class, ~r/^(col|span)[-_]/i) and
      not String.match?(class, @skip_discover_class) and
      String.match?(class, @discover_class)
  end

  defp attr(attrs, name) do
    case List.keyfind(attrs, name, 0) do
      {_, value} when is_binary(value) -> value
      _ -> ""
    end
  end

  defp label_for(selector) do
    Map.get(@preset_labels, selector) ||
      case Regex.run(~r/^[a-z0-9]+\.([A-Za-z0-9_-]+)$/i, selector) do
        [_, class] -> class
        _ -> selector
      end
  end

  defp prefer_distinct_regions(regions) do
    preset_keys = MapSet.new(["" | Map.keys(@preset_labels)])

    {presets, discovered} =
      Enum.split_with(regions, &MapSet.member?(preset_keys, &1.selector))

    discovered =
      discovered
      |> Enum.sort_by(&semantic_rank/1)
      |> Enum.reject(fn region ->
        Enum.any?(presets, &same_region?(&1, region))
      end)
      |> Enum.uniq_by(&{&1.word_count, &1.first_line})

    Enum.uniq_by(presets, & &1.selector) ++ discovered
  end

  defp same_region?(a, b), do: a.word_count == b.word_count and a.first_line == b.first_line

  defp semantic_rank(%{selector: selector}) do
    cond do
      selector == "" ->
        {0, 0, selector}

      selector in @page_builder_selectors ->
        {1, Enum.find_index(@page_builder_selectors, &(&1 == selector)) || 99, selector}

      selector == "[itemprop='articleBody']" ->
        {2, 0, selector}

      selector in ["article", "main"] ->
        {3, 0, selector}

      String.match?(selector, ~r/content|article|entry|post|body|markup/i) ->
        {4, String.length(selector), selector}

      true ->
        {5, String.length(selector), selector}
    end
  end

  defp keep_visible(regions, selected) do
    preset_keys = MapSet.new(Map.keys(@preset_labels))

    {pinned, rest} =
      Enum.split_with(regions, fn region ->
        region.selector == "" or region.recommended or region.selector == selected or
          MapSet.member?(preset_keys, region.selector)
      end)

    extras =
      rest
      |> Enum.filter(&(&1.word_count >= 80))
      |> Enum.sort_by(& &1.word_count, :desc)
      |> Enum.take(4)

    pinned ++ extras
  end

  defp region(html, selector, label, schema) do
    excerpt = excerpt(html, selector)
    recommended? = schema != nil and schema.selector == selector

    %{
      selector: selector,
      label: if(recommended?, do: schema.label, else: label),
      first_line: excerpt.first_line,
      word_count: excerpt.word_count,
      recommended: recommended?,
      selected: false
    }
  end

  defp excerpt(html, ""), do: excerpt_from_html(html)

  defp excerpt(html, selector) do
    case extract(html, selector) do
      nil -> %{first_line: "", word_count: 0}
      selected -> excerpt_from_html(selected)
    end
  end

  defp excerpt_from_html(html) do
    {:ok, doc} = Floki.parse_document(html)
    text = doc |> strip_non_content() |> Floki.text() |> normalize_space()
    words = String.split(text, ~r/\s+/, trim: true)

    %{
      first_line: text |> String.slice(0, 140) |> String.trim(),
      word_count: length(words)
    }
  rescue
    _ -> %{first_line: "", word_count: 0}
  end

  defp node_word_count(node) do
    node |> strip_non_content() |> Floki.text() |> String.split(~r/\s+/, trim: true) |> length()
  end

  defp strip_non_content(nodes) do
    nodes
    |> Floki.filter_out("script")
    |> Floki.filter_out("style")
    |> Floki.filter_out("noscript")
  end

  defp mark_selected(regions, selected) do
    selected = selected || ""

    Enum.map(regions, fn region ->
      %{region | selected: region.selector == selected}
    end)
  end

  defp mark_recommended(regions, schema) do
    chosen =
      cond do
        is_map(schema) and
            Enum.any?(regions, &(&1.selector == schema.selector and &1.word_count > 0)) ->
          schema.selector

        plugin = page_builder_selector(regions) ->
          plugin

        article = article_selector(regions) ->
          article

        true ->
          tightest_content_selector(regions)
      end

    Enum.map(regions, fn region ->
      %{region | recommended: chosen != "" and region.selector == chosen}
    end)
  end

  defp recommended_selector(regions) do
    case Enum.find(regions, & &1.recommended) do
      %{selector: selector} when selector != "" -> selector
      _ -> nil
    end
  end

  defp article_selector(regions) do
    Enum.find_value(@article_selectors, fn selector ->
      case Enum.find(regions, &(&1.selector == selector and &1.word_count >= 80)) do
        %{selector: match} -> match
        _ -> nil
      end
    end)
  end

  defp page_builder_selector(regions) do
    matching =
      Enum.filter(regions, fn region ->
        region.selector in @page_builder_selectors and region.word_count >= 80
      end)

    case matching do
      [] ->
        nil

      list ->
        max_words = Enum.max_by(list, & &1.word_count).word_count
        threshold = div(max_words * 85, 100)

        list
        |> Enum.filter(&(&1.word_count >= threshold))
        |> Enum.min_by(& &1.word_count)
        |> Map.get(:selector)
    end
  end

  defp tightest_content_selector(regions) do
    content = Enum.filter(regions, &(&1.selector != "" and &1.word_count > 0))

    case content do
      [] ->
        ""

        list ->
          max_words = Enum.max_by(list, & &1.word_count).word_count
          threshold = max(80, div(max_words * 2, 5))

          case Enum.filter(list, &(&1.word_count >= threshold)) do
            [] ->
              ""

            kept ->
              kept |> Enum.min_by(& &1.word_count) |> Map.get(:selector)
          end
    end
  end

  defp drop_nested(nodes) do
    htmls = Enum.map(nodes, &{&1, Floki.raw_html(&1)})

    htmls
    |> Enum.reject(fn {_node, html} ->
      Enum.any?(htmls, fn {_other, other} ->
        other != html and String.contains?(other, html)
      end)
    end)
    |> Enum.map(&elem(&1, 0))
  end

  defp keep_substantial(nodes) do
    scored =
      Enum.map(nodes, fn node ->
        {node, node_word_count(node)}
      end)

    max_words = scored |> Enum.map(&elem(&1, 1)) |> Enum.max(fn -> 0 end)
    threshold = max(30, div(max_words, 4))

    kept =
      scored
      |> Enum.filter(fn {_node, words} -> words >= threshold end)
      |> Enum.map(&elem(&1, 0))

    if kept == [], do: Enum.map(scored, &elem(&1, 0)), else: kept
  end

  defp block_from_node({tag, _attrs, _children} = node) do
    text = node |> Floki.text() |> normalize_space()

    if text == "" do
      []
    else
      [
        %{
          xpath: start_xpath(tag, text),
          text: String.slice(text, 0, 140)
        }
      ]
    end
  end

  defp block_from_node(_), do: []

  defp start_xpath(tag, text) do
    snippet = text |> String.slice(0, 48) |> String.replace("'", " ")
    "//#{tag}[contains(., '#{snippet}')]"
  end

  defp drop_before(children, xpath) do
    children = elements_only(children)

    case Enum.find_index(children, &contains_xpath?(&1, xpath)) do
      nil ->
        :miss

      index ->
        [first | tail] = Enum.drop(children, index)

        if Conversion.matches?(first, %{xpath: xpath}) do
          {:ok, [first | tail]}
        else
          case first do
            {tag, attrs, inner} ->
              case drop_before(inner, xpath) do
                {:ok, new_inner} -> {:ok, [{tag, attrs, new_inner} | tail]}
                :miss -> {:ok, [first | tail]}
              end

            _ ->
              {:ok, [first | tail]}
          end
        end
    end
  end

  defp content_children(doc) do
    case Floki.find(doc, "body") do
      [{"body", _, children} | _] -> unwrap(children)
      _ -> unwrap(List.wrap(doc))
    end
  end

  defp unwrap(nodes) do
    case elements_only(List.wrap(nodes)) do
      [{"html", _, children}] -> unwrap(children)
      [{"head", _, _}, {"body", _, children}] -> unwrap(children)
      [{"body", _, children}] -> unwrap(children)
      [{"div", _, children}] -> elements_only(children)
      [{"article", _, children}] -> elements_only(children)
      [{"section", _, children}] -> elements_only(children)
      other -> other
    end
  end

  defp elements_only(nodes) do
    Enum.filter(List.wrap(nodes), &match?({_, _, _}, &1))
  end

  defp contains_xpath?(node, xpath) do
    Conversion.matches?(node, %{xpath: xpath}) or
      case node do
        {_, _, children} -> Enum.any?(children, &contains_xpath?(&1, xpath))
        _ -> false
      end
  end

  defp normalize_space(text) do
    text
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end
end
