defmodule Rss2Nostr.Processing.BodySchema do
  @moduledoc """
  Picks an article-body region without requiring CSS knowledge.

  Known site URL patterns preselect a schema. The compose page then
  shows candidate regions and a "start here" list of opening lines.
  """

  alias Rss2Nostr.Processing.Conversion

  @url_schemas [
    {~r/(^|\.)substack\.com$/i, ".body.markup", "Substack article"},
    {~r/(^|\.)heise\.de$/i, "article.akwa-article", "Heise article"},
    {~r/(^|\.)corbettreport\.com$/i, "div.et_pb_column_0_tb_body", "Corbett article"},
    {~r/(^|\.)manova\.news$/i, "div.article-content", "Manova article"},
    {~r/(^|\.)multipolar-magazin\.de$/i, "div.blog-list-content", "Multipolar article"},
    {~r/(^|\.)freie-medienakademie\.de$/i, ".medienplus-article", "Freie Medienakademie article"}
  ]

  @preset_labels %{
    "div.entry-content" => "WordPress article",
    "article.akwa-article" => "Heise article",
    "article" => "HTML article element",
    "div.et_pb_column_0_tb_body" => "Corbett article",
    "div.article-content" => "Manova article",
    "div.blog-list-content" => "Multipolar article",
    ".medienplus-article" => "Freie Medienakademie article",
    ".body.markup" => "Substack article",
    ".post-content" => "Blog post content"
  }

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

    preset_regions =
      @preset_labels
      |> Enum.filter(fn {selector, _} -> matches?(html, selector) end)
      |> Enum.map(fn {selector, label} ->
        region(html, selector, label, schema)
      end)

    ([region(html, "", "Whole page", schema) | preset_regions])
    |> Enum.uniq_by(& &1.selector)
    |> Enum.sort_by(&{!&1.recommended, -&1.word_count})
    |> mark_selected(selected || (schema && schema.selector) || "")
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
    case Floki.parse_document(html) do
      {:ok, doc} ->
        case Floki.find(doc, selector) do
          [] -> %{first_line: "", word_count: 0}
          found -> excerpt_from_html(Floki.raw_html(found))
        end

      _ ->
        %{first_line: "", word_count: 0}
    end
  rescue
    _ -> %{first_line: "", word_count: 0}
  end

  defp excerpt_from_html(html) do
    text = html |> Floki.parse_document() |> elem(1) |> Floki.text() |> normalize_space()
    words = String.split(text, ~r/\s+/, trim: true)

    %{
      first_line: text |> String.slice(0, 140) |> String.trim(),
      word_count: length(words)
    }
  rescue
    _ -> %{first_line: "", word_count: 0}
  end

  defp mark_selected(regions, selected) do
    selected = selected || ""

    Enum.map(regions, fn region ->
      %{region | selected: region.selector == selected}
    end)
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
