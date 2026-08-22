defmodule Rss2Nostr.Processing.HtmlToMarkdown.Summary do
  @moduledoc false

  alias Rss2Nostr.Processing.HtmlToMarkdown.Embeds

  @spec to_plain(String.t()) :: String.t()
  def to_plain(text) when is_binary(text) do
    text
    |> strip_html()
    |> collapse_whitespace()
  end

  @spec strip_html(String.t()) :: String.t()
  def strip_html(text) do
    if html_fragment?(text) do
      case parse_html(text) do
        {:ok, nodes} ->
          nodes
          |> filter_nodes()
          |> Floki.text(sep: " ")

        _ ->
          text
      end
    else
      text
    end
  end

  @spec collapse_whitespace(String.t()) :: String.t()
  def collapse_whitespace(text) do
    text
    |> String.replace(~r/[\r\n]+/, " ")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  defp parse_html(text) do
    case Floki.parse_fragment(text) do
      {:ok, nodes} -> {:ok, nodes}
      _ -> Floki.parse_document(text)
    end
  end

  defp html_fragment?(text) do
    String.contains?(text, "<") and Regex.match?(~r/<\/?[a-zA-Z]/, text)
  end

  defp filter_nodes(nodes) when is_list(nodes) do
    Enum.flat_map(nodes, &filter_node/1)
  end

  defp filter_node(node) do
    case node do
      {tag, _, _} when tag in ["iframe", "script", "style", "noscript"] ->
        []

      {tag, attrs, children} ->
        if Embeds.summary_soundcloud_chrome?({tag, attrs, children}) do
          []
        else
          [{tag, attrs, filter_nodes(children)}]
        end

      other ->
        [other]
    end
  end
end
