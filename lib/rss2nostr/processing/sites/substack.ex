defmodule Rss2Nostr.Processing.Sites.Substack do
  @moduledoc """
  Substack HTML normalizations used before generic Markdown conversion.

  * Tweet cards (`Twitter2ToDOM` / `twitter-embed`) become a lone status URL
  * Digest post embeds (`DigestPostEmbed`) become a linked thumbnail with the
    title as the image subtitle (`![alt](src "title")` → preview figcaption)
  * Word-style `#_ftnN` / `#_ednN` (and `*ref`) anchors become Markdown footnotes
  * Native Substack `FootnoteAnchorToDOM` / `FootnoteToDOM` become Markdown footnotes
    with the note body on the same line as `[^N]:`
  """

  alias Rss2Nostr.Processing.HtmlToMarkdown

  @selector ".body.markup"

  @spec applies?(map()) :: boolean()
  def applies?(opts) when is_map(opts) do
    substack_host?(opts[:url] || opts["url"]) or
      substack_selector?(opts[:body_selector] || opts["body_selector"])
  end

  def applies?(_), do: false

  @spec preprocess(String.t()) :: String.t()
  def preprocess(html) when html in [nil, ""], do: html

  def preprocess(html) when is_binary(html) do
    html = HtmlToMarkdown.preserve_inline_spaces(html)

    case Floki.parse_document(html) do
      {:ok, doc} -> doc |> rewrite_nodes() |> Floki.raw_html()
      _ -> html
    end
  rescue
    _ -> html
  end

  @spec substack_host?(term()) :: boolean()
  defp substack_host?(url) when is_binary(url) and url != "" do
    host = url |> URI.parse() |> Map.get(:host) |> to_string() |> String.downcase()
    host == "substack.com" or String.ends_with?(host, ".substack.com")
  rescue
    _ -> false
  end

  defp substack_host?(_), do: false

  @spec substack_selector?(term()) :: boolean()
  defp substack_selector?(selector) when is_binary(selector) do
    String.trim(selector) == @selector
  end

  defp substack_selector?(_), do: false

  @spec rewrite_nodes(term()) :: term()
  defp rewrite_nodes(nodes) when is_list(nodes), do: Enum.map(nodes, &rewrite_node/1)
  defp rewrite_nodes(node), do: rewrite_node(node)

  @spec rewrite_node(term()) :: term()
  defp rewrite_node({"a", attrs, children}) do
    cond do
      footnote = footnote_link(attr(attrs, "href"), children) ->
        footnote_text(footnote)

      tweet_embed?(attrs, children) ->
        tweet_paragraph(attrs, children)

      true ->
        {"a", attrs, rewrite_nodes(children)}
    end
  end

  defp rewrite_node({"div", attrs, children}) do
    cond do
      footnote_definition_div?(attrs) ->
        rewrite_footnote_definition(children)

      digest_post_embed?(attrs) ->
        rewrite_digest_post_embed(children)

      tweet_embed_attrs?(attrs) ->
        case tweet_url(attrs, children) do
          url when is_binary(url) -> tweet_paragraph(attrs, children)
          _ -> {"div", attrs, rewrite_nodes(children)}
        end

      true ->
        {"div", attrs, rewrite_nodes(children)}
    end
  end

  defp rewrite_node({tag, attrs, children}), do: {tag, attrs, rewrite_nodes(children)}
  defp rewrite_node(other), do: other

  @spec footnote_link(term(), list()) :: {:reference | :definition, String.t()} | nil
  defp footnote_link(href, children) when is_binary(href) do
    case footnote_fragment(uri_fragment(href)) do
      {kind, frag_id} -> {kind, visible_footnote_id(children) || frag_id}
      nil -> nil
    end
  end

  defp footnote_link(_, _), do: nil

  # Word/Substack pastes often keep the original-site URL. The fragment
  # (`#_ftnN`, `#_ednN`, and `*ref`) marks the note; the visible `[N]`
  # is the number readers see (endnote ids may continue from part I).
  @spec uri_fragment(String.t()) :: String.t() | nil
  defp uri_fragment(href) do
    case URI.parse(href) do
      %URI{fragment: frag} when is_binary(frag) and frag != "" -> frag
      _ -> nil
    end
  rescue
    _ -> nil
  end

  @spec footnote_fragment(term()) :: {:reference | :definition, String.t()} | nil
  defp footnote_fragment(frag) when is_binary(frag) do
    cond do
      match = Regex.run(~r/^_?(?:ftnref|fnref|footnoteref|ednref|endnoteref)(\d+)$/i, frag) ->
        {:definition, Enum.at(match, 1)}

      match = Regex.run(~r/^footnote-anchor-(\d+)$/i, frag) ->
        {:definition, Enum.at(match, 1)}

      match = Regex.run(~r/^footnote-(\d+)$/i, frag) ->
        {:reference, Enum.at(match, 1)}

      match = Regex.run(~r/^_?(?:ftn|fn|footnote|edn|endnote)(\d+)$/i, frag) ->
        {:reference, Enum.at(match, 1)}

      true ->
        nil
    end
  end

  defp footnote_fragment(_), do: nil

  @spec visible_footnote_id(list()) :: String.t() | nil
  defp visible_footnote_id(children) do
    text = {"a", [], List.wrap(children)} |> Floki.text() |> String.trim()

    case Regex.run(~r/^\[?(\d+)\]?$/, text) do
      [_, id] -> id
      _ -> nil
    end
  end

  @spec digest_post_embed?(list()) :: boolean()
  defp digest_post_embed?(attrs) do
    component = attr(attrs, "data-component-name", "")
    class = attrs |> attr("class", "") |> String.downcase()

    component == "DigestPostEmbed" or
      String.contains?(class, "digestpostembed") or
      String.contains?(class, "digest-post")
  end

  # Card chrome (thumbnail + title + author + "read more") becomes a linked
  # figure whose figcaption carries the title as a visible image subtitle.
  @spec rewrite_digest_post_embed(list()) :: Floki.html_node()
  defp rewrite_digest_post_embed(children) do
    href = digest_href(children)
    title = digest_title(children)
    image = digest_image(children)
    caption = digest_caption(children)
    subtitle = present_text(caption) || present_text(title)

    blocks =
      cond do
        is_binary(href) and is_binary(image) and image != "" and is_binary(subtitle) ->
          [
            {"figure", [],
             [
               {"a", [{"href", href}],
                [{"img", [{"src", image}, {"alt", present_text(title) || ""}], []}]},
               {"figcaption", [], [subtitle]}
             ]}
          ]

        is_binary(href) and is_binary(image) and image != "" ->
          [
            {"p", [],
             [{"a", [{"href", href}], [{"img", [{"src", image}, {"alt", ""}], []}]}]}
          ]

        is_binary(href) and is_binary(title) and title != "" ->
          [{"h2", [], [{"a", [{"href", href}], [title]}]}]

        true ->
          []
      end

    caption_used_as_subtitle? =
      is_binary(image) and image != "" and is_binary(subtitle) and subtitle == present_text(caption)

    blocks =
      if present_text(caption) && not caption_used_as_subtitle? do
        blocks ++ [{"p", [], [caption]}]
      else
        blocks
      end

    case blocks do
      [] -> {"div", [], rewrite_nodes(children)}
      [only] -> only
      many -> {"div", [], many}
    end
  end

  @spec present_text(term()) :: String.t() | nil
  defp present_text(text) when is_binary(text) do
    case text |> String.trim() |> unwrap_quotes() do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present_text(_), do: nil

  # Digest headings often wrap the title in typographic/ASCII quotes.
  @spec unwrap_quotes(String.t()) :: String.t()
  defp unwrap_quotes(text) do
    case Regex.run(~r/^["“”„«»](.+)["“”„«»]$/u, text) do
      [_, inner] -> String.trim(inner)
      _ -> text
    end
  end

  @spec digest_href(term()) :: String.t() | nil
  defp digest_href(nodes) when is_list(nodes) do
    Enum.find_value(nodes, &digest_href/1)
  end

  defp digest_href({"a", attrs, children}) do
    href = attr(attrs, "href")

    if digest_post_url?(href) do
      href
    else
      digest_href(children)
    end
  end

  defp digest_href({_, _, children}), do: digest_href(children)
  defp digest_href(_), do: nil

  @spec digest_post_url?(term()) :: boolean()
  defp digest_post_url?(href) when is_binary(href) do
    uri = URI.parse(href)
    path = uri.path || ""

    http_url?(href) and String.contains?(path, "/p/") and
      not String.ends_with?(path, "/comments")
  rescue
    _ -> false
  end

  defp digest_post_url?(_), do: false

  @spec digest_title(term()) :: String.t() | nil
  defp digest_title(nodes) when is_list(nodes) do
    Enum.find_value(nodes, &digest_title/1)
  end

  defp digest_title({tag, _, children}) when tag in ~w(h1 h2 h3 h4 h5 h6) do
    text = {"span", [], List.wrap(children)} |> Floki.text() |> String.trim()
    if text != "", do: text
  end

  defp digest_title({_, _, children}), do: digest_title(children)
  defp digest_title(_), do: nil

  @spec digest_image(term()) :: String.t() | nil
  defp digest_image(nodes) when is_list(nodes) do
    Enum.find_value(nodes, &digest_image/1)
  end

  defp digest_image({"img", attrs, _}) do
    src = attr(attrs, "src") || attr(attrs, "data-src")
    if is_binary(src) and String.trim(src) != "", do: String.trim(src)
  end

  defp digest_image({_, _, children}), do: digest_image(children)
  defp digest_image(_), do: nil

  @spec digest_caption(term()) :: String.t() | nil
  defp digest_caption(nodes) when is_list(nodes) do
    Enum.find_value(nodes, &digest_caption/1)
  end

  defp digest_caption({"p", attrs, children}) do
    if class_token?(attrs, "caption") do
      text = {"p", [], children} |> Floki.text() |> String.trim()
      if text != "", do: text
    else
      digest_caption(children)
    end
  end

  defp digest_caption({_, _, children}), do: digest_caption(children)
  defp digest_caption(_), do: nil

  @spec http_url?(String.t()) :: boolean()
  defp http_url?(url) do
    uri = URI.parse(url)
    uri.scheme in ["http", "https"] and is_binary(uri.host) and uri.host != ""
  rescue
    _ -> false
  end

  @spec footnote_definition_div?(list()) :: boolean()
  defp footnote_definition_div?(attrs) do
    attr(attrs, "data-component-name", "") == "FootnoteToDOM" or class_token?(attrs, "footnote")
  end

  @spec rewrite_footnote_definition(list()) :: Floki.html_node()
  defp rewrite_footnote_definition(children) do
    id = footnote_definition_id(children)

    inner =
      children
      |> footnote_content_inner()
      |> rewrite_nodes()
      |> unwrap_single_paragraph()

    {"p", [], ["[^#{id}]: " | inner]}
  end

  @spec footnote_definition_id(list()) :: String.t()
  defp footnote_definition_id(children) do
    case find_footnote_number_link(children) do
      {"a", attrs, link_children} = node ->
        visible_footnote_id(link_children) ||
          id_from_footnote_attr(attr(attrs, "id")) ||
          case footnote_link(attr(attrs, "href"), link_children) do
            {_, id} -> id
            _ -> node |> Floki.text() |> String.trim()
          end

      _ ->
        "1"
    end
  end

  @spec id_from_footnote_attr(term()) :: String.t() | nil
  defp id_from_footnote_attr(id) when is_binary(id) do
    case Regex.run(~r/^footnote-(\d+)$/i, id) do
      [_, n] -> n
      _ -> nil
    end
  end

  defp id_from_footnote_attr(_), do: nil

  @spec find_footnote_number_link(term()) :: Floki.html_node() | nil
  defp find_footnote_number_link(nodes) when is_list(nodes) do
    Enum.find_value(nodes, &find_footnote_number_link/1)
  end

  defp find_footnote_number_link({"a", attrs, _} = node) do
    if class_token?(attrs, "footnote-number") or id_from_footnote_attr(attr(attrs, "id")) do
      node
    end
  end

  defp find_footnote_number_link({_, _, children}), do: find_footnote_number_link(children)
  defp find_footnote_number_link(_), do: nil

  @spec footnote_content_inner(list()) :: list()
  defp footnote_content_inner(nodes) when is_list(nodes) do
    content =
      Enum.find_value(nodes, fn
        {"div", attrs, inner} ->
          if class_token?(attrs, "footnote-content"), do: inner

        _ ->
          nil
      end) || Enum.reject(nodes, &footnote_number_link?/1)

    # Last native Substack footnotes often append <hr> + subscribe CTA
    # inside .footnote-content. That extra markup prevents unwrapping the
    # note <p>, so the URL lands on the next line after [^N]:.
    content
    |> Enum.reject(&blank_node?/1)
    |> Enum.take_while(&(not footnote_trailing_chrome?(&1)))
    |> Enum.reject(&blank_node?/1)
  end

  @spec footnote_number_link?(term()) :: boolean()
  defp footnote_number_link?(node), do: find_footnote_number_link(node) == node

  @spec footnote_trailing_chrome?(term()) :: boolean()
  defp footnote_trailing_chrome?({"hr", _, _}), do: true

  defp footnote_trailing_chrome?({_, attrs, children}) do
    subscribe_widget?(attrs) or hr_only_wrapper?(children)
  end

  defp footnote_trailing_chrome?(_), do: false

  @spec subscribe_widget?(list()) :: boolean()
  defp subscribe_widget?(attrs) do
    class_token?(attrs, "subscription-widget-wrap") or
      class_token?(attrs, "subscription-widget") or
      class_token?(attrs, "subscribe-widget") or
      attr(attrs, "data-component-name", "") == "SubscribeWidget"
  end

  @spec hr_only_wrapper?(list()) :: boolean()
  defp hr_only_wrapper?(children) do
    case Enum.reject(children, &blank_node?/1) do
      [{"hr", _, _}] -> true
      _ -> false
    end
  end

  @spec blank_node?(term()) :: boolean()
  defp blank_node?(text) when is_binary(text), do: String.trim(text) == ""

  defp blank_node?({"p", _, children}) do
    children |> Enum.reject(&blank_node?/1) == []
  end

  defp blank_node?(_), do: false

  @spec unwrap_single_paragraph(list()) :: list()
  defp unwrap_single_paragraph(nodes) do
    case Enum.reject(nodes, &blank_node?/1) do
      [{"p", _, inner}] -> inner
      other -> other
    end
  end

  @spec class_token?(list(), String.t()) :: boolean()
  defp class_token?(attrs, token) do
    attrs
    |> attr("class", "")
    |> String.split()
    |> Enum.any?(&(&1 == token))
  end

  @spec footnote_text({:reference | :definition, String.t()}) :: String.t()
  defp footnote_text({:reference, id}), do: "[^#{id}]"
  defp footnote_text({:definition, id}), do: "[^#{id}]: "

  @spec tweet_paragraph(list(), list()) :: Floki.html_node()
  defp tweet_paragraph(attrs, children) do
    case tweet_url(attrs, children) do
      url when is_binary(url) -> {"p", [], [url]}
      _ -> {"p", [], []}
    end
  end

  @spec tweet_embed?(list(), list()) :: boolean()
  defp tweet_embed?(attrs, children) do
    href = attr(attrs, "href", "")

    tweet_status_url?(href) and
      (tweet_embed_attrs?(attrs) or tweet_card_children?(children))
  end

  @spec tweet_embed_attrs?(list()) :: boolean()
  defp tweet_embed_attrs?(attrs) do
    class = attrs |> attr("class", "") |> String.downcase()
    component = attr(attrs, "data-component-name", "")
    data_attrs = attr(attrs, "data-attrs", "")

    String.contains?(class, "twitter-embed") or
      String.contains?(class, "twitter-tweet") or
      component == "Twitter2ToDOM" or
      tweet_data_attrs?(data_attrs)
  end

  @spec tweet_card_children?(list()) :: boolean()
  defp tweet_card_children?(children) do
    Enum.any?(children, fn
      {tag, _, _} when tag in ["div", "picture", "figure", "section", "article"] -> true
      _ -> false
    end)
  end

  @spec tweet_url(list(), list()) :: String.t() | nil
  defp tweet_url(attrs, children) do
    [
      attr(attrs, "href"),
      tweet_url_from_data_attrs(attr(attrs, "data-attrs", "")),
      tweet_url_from_children(children)
    ]
    |> Enum.find(&tweet_status_url?/1)
  end

  @spec tweet_url_from_children(term()) :: String.t() | nil
  defp tweet_url_from_children(nodes) when is_list(nodes) do
    Enum.find_value(nodes, fn
      {_, child_attrs, child_children} -> tweet_url(child_attrs, child_children)
      _ -> nil
    end)
  end

  defp tweet_url_from_children(_), do: nil

  @spec tweet_url_from_data_attrs(term()) :: String.t() | nil
  defp tweet_url_from_data_attrs(data_attrs) when is_binary(data_attrs) and data_attrs != "" do
    case Jason.decode(data_attrs) do
      {:ok, %{"url" => url}} when is_binary(url) -> url
      _ -> nil
    end
  end

  defp tweet_url_from_data_attrs(_), do: nil

  @spec tweet_data_attrs?(term()) :: boolean()
  defp tweet_data_attrs?(data_attrs) when is_binary(data_attrs) and data_attrs != "" do
    tweet_status_url?(tweet_url_from_data_attrs(data_attrs))
  end

  defp tweet_data_attrs?(_), do: false

  @spec tweet_status_url?(term()) :: boolean()
  defp tweet_status_url?(url) when is_binary(url) do
    uri = URI.parse(url)
    host = uri.host || ""
    path = uri.path || ""

    tweet_host?(host) and Regex.match?(~r{^/[^/]+/status/\d+}i, path)
  rescue
    _ -> false
  end

  defp tweet_status_url?(_), do: false

  @spec tweet_host?(String.t()) :: boolean()
  defp tweet_host?(host) do
    host = String.downcase(host)

    host in [
      "x.com",
      "twitter.com",
      "www.x.com",
      "www.twitter.com",
      "mobile.twitter.com",
      "mobile.x.com"
    ]
  end

  @spec attr(list(), String.t(), term()) :: term()
  defp attr(attrs, name, default \\ nil) do
    case List.keyfind(attrs, name, 0) do
      {_, value} -> value
      nil -> default
    end
  end
end
