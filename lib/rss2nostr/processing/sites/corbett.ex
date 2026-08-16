defmodule Rss2Nostr.Processing.Sites.Corbett do
  @moduledoc """
  Corbett Report HTML normalizations used before generic Markdown conversion.

  * “WATCH ON:” rows become a heading plus one paragraph per remaining
    platform link
  * Links that already appear as an iframe embed (Odysee, YouTube, …)
    are omitted from that list
  """

  alias Rss2Nostr.Processing.{Conversion, HtmlToMarkdown}

  @selector "div.et_pb_column_0_tb_body"

  @spec applies?(map()) :: boolean()
  def applies?(opts) when is_map(opts) do
    corbett_host?(opts[:url] || opts["url"]) or
      corbett_selector?(opts[:body_selector] || opts["body_selector"])
  end

  def applies?(_), do: false

  @spec preprocess(String.t()) :: String.t()
  def preprocess(html) when html in [nil, ""], do: html

  def preprocess(html) when is_binary(html) do
    case Floki.parse_document(html) do
      {:ok, doc} ->
        embeds = iframe_watch_urls(doc)
        doc |> rewrite_nodes(embeds) |> Floki.raw_html()

      _ ->
        html
    end
  rescue
    _ -> html
  end

  defp corbett_host?(url) when is_binary(url) and url != "" do
    host = url |> URI.parse() |> Map.get(:host) |> to_string() |> String.downcase()
    host == "corbettreport.com" or String.ends_with?(host, ".corbettreport.com")
  rescue
    _ -> false
  end

  defp corbett_host?(_), do: false

  defp corbett_selector?(selector) when is_binary(selector) do
    String.trim(selector) == @selector
  end

  defp corbett_selector?(_), do: false

  defp iframe_watch_urls(doc) do
    doc
    |> Floki.find("iframe")
    |> Enum.flat_map(fn
      {"iframe", attrs, _} ->
        src = attr(attrs, "src")

        case HtmlToMarkdown.iframe_watch_url(src) do
          url when is_binary(url) -> [url]
          _ -> []
        end

      _ ->
        []
    end)
  end

  defp rewrite_nodes(nodes, embeds) when is_list(nodes) do
    Enum.flat_map(nodes, &expand_or_rewrite(&1, embeds))
  end

  defp expand_or_rewrite({tag, attrs, children} = node, embeds) do
    if watch_on_row?(node) do
      expand_watch_on(children, embeds)
    else
      [{tag, attrs, rewrite_nodes(children, embeds)}]
    end
  end

  defp expand_or_rewrite(other, _), do: [other]

  defp watch_on_row?({"p", _attrs, children}) do
    text = children |> Floki.text() |> String.downcase()
    String.match?(text, ~r/watch\s+on\s*:/) and Conversion.links(children) != []
  end

  defp watch_on_row?(_), do: false

  defp expand_watch_on(children, embeds) do
    links =
      children
      |> Conversion.links()
      |> Enum.reject(fn {_text, href} ->
        Enum.any?(embeds, &HtmlToMarkdown.same_video?(href, &1))
      end)

    case links do
      [] ->
        []

      _ ->
        heading = {"p", [], [{"strong", [], ["WATCH ON:"]}]}

        link_nodes =
          Enum.map(links, fn {text, href} ->
            {"p", [], [{"a", [{"href", href}], [watch_on_label(text, href)]}]}
          end)

        [heading | link_nodes]
    end
  end

  defp watch_on_label(text, href) do
    if youtube_url?(href), do: "YOUTUBE", else: text
  end

  defp youtube_url?(href) when is_binary(href) do
    host = href |> URI.parse() |> Map.get(:host) |> to_string() |> String.downcase()
    String.contains?(host, "youtube.com") or String.contains?(host, "youtu.be")
  rescue
    _ -> false
  end

  defp youtube_url?(_), do: false

  defp attr(attrs, name) do
    case List.keyfind(attrs, name, 0) do
      {_, value} -> value
      nil -> ""
    end
  end
end
