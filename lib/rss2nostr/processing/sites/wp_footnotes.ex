defmodule Rss2Nostr.Processing.Sites.WpFootnotes do
  @moduledoc """
  Converts WordPress Footnotes Made Easy markup to Markdown footnotes.

  Identifier: `<a href="#footnote_1_8346" class="footnote-identifier-link">1</a>`
  Definition: `<ol class="footnotes"><li id="footnote_1_8346">…</li></ol>`
  """

  alias Rss2Nostr.Processing.HtmlToMarkdown

  @spec applies?(map()) :: boolean()
  def applies?(_opts), do: true

  @spec preprocess(String.t()) :: String.t()
  def preprocess(html) when html in [nil, ""], do: html

  def preprocess(html) when is_binary(html) do
    html = HtmlToMarkdown.preserve_inline_spaces(html)

    case Floki.parse_document(html) do
      {:ok, doc} ->
        if has_wp_footnotes?(doc) do
          doc |> rewrite_nodes() |> Floki.raw_html()
        else
          html
        end

      _ ->
        html
    end
  rescue
    _ -> html
  end

  defp rewrite_nodes(nodes) when is_list(nodes) do
    Enum.flat_map(nodes, fn node ->
      case rewrite_node(node) do
        list when is_list(list) -> list
        other -> [other]
      end
    end)
  end

  defp rewrite_node({"a", attrs, children}) do
    cond do
      identifier_link?(attrs) ->
        "[^#{footnote_id(attrs, children)}]"

      back_link?(attrs) ->
        ""

      true ->
        {"a", attrs, rewrite_nodes(children)}
    end
  end

  defp rewrite_node({"span", attrs, children}) do
    if class_token?(attrs, "footnote-back-link-wrapper") do
      ""
    else
      {"span", attrs, rewrite_nodes(children)}
    end
  end

  defp rewrite_node({"ol", attrs, children}) do
    children = rewrite_nodes(children)

    if class_token?(attrs, "footnotes") do
      children
    else
      {"ol", attrs, children}
    end
  end

  defp rewrite_node({"li", attrs, children}) do
    children = rewrite_nodes(children)

    case footnote_li_id(attrs, children) do
      id when is_binary(id) ->
        {"p", [], ["[^#{id}]: " | children]}

      nil ->
        {"li", attrs, children}
    end
  end

  defp rewrite_node({tag, attrs, children}), do: {tag, attrs, rewrite_nodes(children)}
  defp rewrite_node(other), do: other

  defp has_wp_footnotes?(nodes) when is_list(nodes), do: Enum.any?(nodes, &wp_footnote_node?/1)

  defp wp_footnote_node?({"a", attrs, children}) do
    identifier_link?(attrs) or back_link?(attrs) or has_wp_footnotes?(children)
  end

  defp wp_footnote_node?({"ol", attrs, children}) do
    class_token?(attrs, "footnotes") or has_wp_footnotes?(children)
  end

  defp wp_footnote_node?({_, _, children}), do: has_wp_footnotes?(children)
  defp wp_footnote_node?(_), do: false

  defp identifier_link?(attrs) do
    class_token?(attrs, "footnote-identifier-link") or
      match?({:reference, _}, fragment_kind(attrs))
  end

  defp back_link?(attrs) do
    class_token?(attrs, "footnote-back-link") or
      match?({:definition, _}, fragment_kind(attrs))
  end

  defp footnote_id(attrs, children) do
    visible = visible_id(children)
    if visible, do: visible, else: fragment_id(attrs) || "1"
  end

  defp footnote_li_id(attrs, children) do
    cond do
      id = def_id_from_attr(attr(attrs, "id")) ->
        id

      class_token?(attrs, "footnote") ->
        fragment_id_from_nodes(children) || visible_id(children)

      true ->
        nil
    end
  end

  defp fragment_kind(attrs) do
    attrs
    |> attr("href")
    |> uri_fragment()
    |> classify_fragment()
  end

  defp fragment_id(attrs) do
    case fragment_kind(attrs) do
      {_kind, id} -> id
      _ -> nil
    end
  end

  defp classify_fragment(frag) when is_binary(frag) do
    cond do
      match = Regex.run(~r/^footnote_(\d+)(?:_\d+)?$/i, frag) ->
        {:reference, Enum.at(match, 1)}

      match = Regex.run(~r/^identifier_(\d+)(?:_\d+)?$/i, frag) ->
        {:definition, Enum.at(match, 1)}

      true ->
        nil
    end
  end

  defp classify_fragment(_), do: nil

  defp def_id_from_attr(id) when is_binary(id) do
    case classify_fragment(id) do
      {:reference, n} -> n
      _ -> nil
    end
  end

  defp def_id_from_attr(_), do: nil

  defp fragment_id_from_nodes(nodes) do
    Enum.find_value(List.wrap(nodes), fn
      text when is_binary(text) ->
        case Regex.run(~r/\[\^(\d+)\]/, text) do
          [_, n] -> n
          _ -> nil
        end

      {_, _, children} ->
        fragment_id_from_nodes(children)

      _ ->
        nil
    end)
  end

  defp visible_id(children) do
    text = {"a", [], List.wrap(children)} |> Floki.text() |> String.trim()

    case Regex.run(~r/^\[?(\d+)\]?$/, text) do
      [_, n] -> n
      _ -> nil
    end
  end

  defp uri_fragment(href) when is_binary(href) do
    case URI.parse(href) do
      %URI{fragment: frag} when is_binary(frag) and frag != "" -> frag
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp uri_fragment(_), do: nil

  defp class_token?(attrs, token) do
    attrs
    |> attr("class", "")
    |> String.split(~r/\s+/, trim: true)
    |> Enum.member?(token)
  end

  defp attr(attrs, name, default \\ nil) do
    Enum.find_value(attrs, default, fn
      {^name, value} -> value
      _ -> nil
    end)
  end
end
