defmodule Rss2Nostr.Processing.HtmlToMarkdown.LinkTags do
  @moduledoc false

  @parent Rss2Nostr.Processing.HtmlToMarkdown

  alias Rss2Nostr.Processing.ImageExtractor
  alias Rss2Nostr.Processing.HtmlToMarkdown.{Dom, Embeds, Links, TrackingParams}

  @type process_nodes :: (list() -> String.t())

  @spec process_social_bar(list()) :: String.t()
  def process_social_bar(children) do
    links = collect_http_links(children)
    caption = social_bar_caption(children)

    markdown =
      case {links, caption} do
        {[%{href: href, icon: icon}], caption} when caption != "" ->
          Links.markdown_icon_link(href, caption, icon, social_bar_icon_order(children))

        {[%{href: href, label: label, icon: icon}], _} ->
          Links.markdown_icon_link(href, label, icon)

        {links, _} ->
          Enum.map_join(links, " · ", fn %{href: href, label: label, icon: icon} ->
            Links.markdown_icon_link(href, label, icon)
          end)
      end

    if String.trim(markdown) == "", do: "", else: "\n\n#{markdown}\n\n"
  end

  @spec process_link(list(), list(), process_nodes()) :: String.t()
  def process_link(attrs, children, process_nodes) do
    href = attrs |> Dom.get_attr("href") |> Links.normalize_href()

    cond do
      is_nil(href) or href == "" ->
        process_link_children(children, process_nodes) |> String.trim()

      relative_path?(href) ->
        ""

      discard_link?(href) ->
        ""

      Embeds.soundcloud_widget_chrome?(href) ->
        ""

      true ->
        text = process_link_children(children, process_nodes) |> String.trim()

        clean_href =
          href
          |> Links.ensure_absolute_url()
          |> TrackingParams.remove()
          |> Embeds.with_soundcloud_params()

        label = link_display_label(attrs, children, text, clean_href)

        icon =
          if Links.tweet_status_link?(clean_href) and text != "" and
               not url_like_label?(text, clean_href) do
            nil
          else
            Links.network_icon_url(children, label, clean_href)
          end

        if icon do
          Links.markdown_icon_link(clean_href, label, icon, Links.link_icon_order(children, text))
        else
          markdown_media_link(label, clean_href, Dom.get_attr(attrs, "title"))
        end
    end
  end

  @spec process_link_children(list(), process_nodes()) :: String.t()
  defp process_link_children(children, process_nodes) do
    Process.put({@parent, :in_link}, true)

    try do
      process_nodes.(children)
    after
      Process.delete({@parent, :in_link})
    end
  end

  @spec collect_http_links(list()) :: [%{href: String.t(), label: String.t(), icon: String.t() | nil}]
  defp collect_http_links(nodes) do
    Enum.flat_map(List.wrap(nodes), fn
      {"a", attrs, inner} ->
        href = attrs |> Dom.get_attr("href") |> Links.normalize_href()

        if is_binary(href) and http_url?(href) and not discard_link?(href) do
          label = link_fallback_label(attrs, inner, href)

          [
            %{
              href: TrackingParams.remove(href),
              label: label,
              icon: Links.network_icon_url(inner, label, href)
            }
          ]
        else
          []
        end

      {_, _, inner} ->
        collect_http_links(inner)

      _ ->
        []
    end)
  end

  @spec social_bar_caption(list()) :: String.t()
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

  @spec social_bar_icon_order(list()) :: Links.icon_order()
  defp social_bar_icon_order(nodes) do
    if first_social_signal(nodes) == :caption, do: :label_first, else: :icon_first
  end

  @spec first_social_signal(list()) :: :link | :caption | nil
  defp first_social_signal(nodes) do
    Enum.find_value(List.wrap(nodes), fn
      {"a", _, _} ->
        :link

      {tag, _, inner} when tag in ~w(span p) ->
        text = inner |> Floki.text() |> String.trim()
        if text == "", do: first_social_signal(inner), else: :caption

      {_, _, inner} ->
        first_social_signal(inner)

      text when is_binary(text) ->
        if String.trim(text) == "", do: nil, else: :caption

      _ ->
        nil
    end)
  end

  @spec markdown_media_link(String.t(), String.t(), term()) :: String.t()
  defp markdown_media_link(text, href, title) do
    if media_file_url?(href) and present_title?(title) do
      ~s|[#{text}](#{href} "#{escape_md_title(title)}")|
    else
      "[#{text}](#{href})"
    end
  end

  @spec link_display_label(list(), list(), String.t(), String.t()) :: String.t()
  defp link_display_label(attrs, children, text, href) do
    if url_like_label?(text, href) do
      link_fallback_label(attrs, children, href)
    else
      text
    end
  end

  @spec url_like_label?(String.t(), String.t()) :: boolean()
  defp url_like_label?(text, href) do
    stripped = Links.strip_url_noise(text)

    stripped == "" or
      stripped == Links.strip_url_noise(href) or
      match?({_, _}, Links.platform_for_href(text))
  end

  @spec link_fallback_label(list(), list(), String.t()) :: String.t()
  defp link_fallback_label(attrs, children, href) do
    aria = Dom.get_attr(attrs, "aria-label")
    title = Dom.get_attr(attrs, "title")

    cond do
      present_title?(aria) ->
        String.trim(aria)

      present_title?(title) ->
        String.trim(title)

      label = Links.icon_network_label(children) ->
        label

      true ->
        case Links.platform_for_href(href) do
          {label, _} -> label
          _ -> href
        end
    end
  end

  @spec media_file_url?(String.t()) :: boolean()
  defp media_file_url?(href) do
    ImageExtractor.audio_url?(href) or ImageExtractor.video_url?(href)
  end

  @spec present_title?(term()) :: boolean()
  defp present_title?(title) when is_binary(title), do: String.trim(title) != ""
  defp present_title?(_), do: false

  @spec escape_md_title(String.t()) :: String.t()
  defp escape_md_title(title) do
    String.replace(title, "\"", "'")
  end

  @spec relative_path?(String.t()) :: boolean()
  defp relative_path?(href) do
    String.starts_with?(href, "/") and not String.starts_with?(href, "//")
  end

  @spec http_url?(String.t()) :: boolean()
  defp http_url?(url) when is_binary(url) do
    uri = URI.parse(url)
    uri.scheme in ["http", "https"] and is_binary(uri.host) and uri.host != ""
  rescue
    _ -> false
  end

  @spec discard_link?(String.t()) :: boolean()
  defp discard_link?(href) do
    uri = URI.parse(href)
    path = uri.path || ""

    String.ends_with?(path, "/subscribe") or
      String.ends_with?(path, "/comments") or
      share_action?(uri.query)
  rescue
    _ -> false
  end

  @spec share_action?(term()) :: boolean()
  defp share_action?(nil), do: false

  defp share_action?(query) when is_binary(query) do
    query
    |> URI.decode_query()
    |> Map.get("action")
    |> Kernel.==("share")
  end
end
