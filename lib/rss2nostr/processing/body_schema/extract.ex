defmodule Rss2Nostr.Processing.BodySchema.Extract do
  @moduledoc false

  alias Rss2Nostr.Processing.{Conversion, HtmlToMarkdown}

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

  @spec strip_non_content(list()) :: list()
  def strip_non_content(nodes) do
    nodes
    |> Floki.filter_out("script")
    |> Floki.filter_out("style")
    |> Floki.filter_out("noscript")
  end

  @spec normalize_space(String.t()) :: String.t()
  def normalize_space(text) do
    text
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  @spec node_word_count(tuple() | list()) :: non_neg_integer()
  def node_word_count(node) do
    node |> strip_non_content() |> Floki.text() |> String.split(~r/\s+/, trim: true) |> length()
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
end
