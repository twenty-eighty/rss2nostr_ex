defmodule Rss2Nostr.Processing.Sites.Corbett do
  @moduledoc """
  Corbett Report HTML normalizations used before generic Markdown conversion.

  * Short “Watch …” rows with video-platform links become a heading
    plus one paragraph per remaining platform link
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
    html = HtmlToMarkdown.preserve_inline_spaces(html)

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

  # A lone "Watch the hearing:" show-note with one YouTube URL is not
  # a platform row. Require a Watch-on phrase or two video hosts, and
  # keep the paragraph short so prose does not match.
  @watch_on_max_len 240
  @video_hosts ~w(
    youtube.com youtu.be odysee.com bitchute.com rumble.com
    archive.org rokfin.com minds.com substack.com
  )

  defp watch_on_row?({"p", _attrs, children}) do
    text = children |> Floki.text() |> String.downcase() |> String.trim()
    links = Conversion.links(children)

    String.starts_with?(text, "watch") and links != [] and
      String.length(text) <= @watch_on_max_len and
      (watch_on_phrase?(text) or video_platform_count(links) >= 2)
  end

  defp watch_on_row?(_), do: false

  defp watch_on_phrase?(text) do
    String.match?(text, ~r/\Awatch(?:\s+\w+){0,4}\s+on(?:\s*:|\b)/u)
  end

  defp video_platform_count(links) do
    Enum.count(links, fn {_text, href} -> video_platform_href?(href) end)
  end

  defp video_platform_href?(href) when is_binary(href) do
    uri = URI.parse(href)
    host = uri.host |> to_string() |> String.downcase()
    path = uri.path |> to_string() |> String.downcase()

    Enum.any?(@video_hosts, &String.contains?(host, &1)) or String.ends_with?(path, ".mp4")
  rescue
    _ -> false
  end

  defp video_platform_href?(_), do: false

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
