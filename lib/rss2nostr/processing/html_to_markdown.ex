defmodule Rss2Nostr.Processing.HtmlToMarkdown do
  @moduledoc """
  Converts HTML to Markdown with special handling for:
  - Tracking parameter removal from URLs
  - YouTube, SoundCloud, Podbean embeds
  - Responsive images (srcset handling)
  - Figures with captions

  Site-specific rewrites (Substack tweet cards, footnotes) live in
  `Rss2Nostr.Processing.Sites` and run before this converter.
  """

  require Logger

  alias Rss2Nostr.Processing.{ImageExtractor, Youtube}

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
  """
  @spec convert(String.t() | nil, keyword()) :: String.t() | nil
  def convert(html, opts \\ [])
  def convert(nil, _opts), do: nil
  def convert("", _opts), do: nil

  def convert(html, opts) when is_binary(html) do
    skip = Keyword.get(opts, :skip_classes, @default_skip_classes)
    rules = Keyword.get(opts, :conversion_rules, [])
    Process.put({__MODULE__, :skip_classes}, normalize_skip_classes(skip))
    Process.put({__MODULE__, :conversion_rules}, rules)

    try do
      html
      |> preprocess_html()
      |> Floki.parse_document!()
      |> process_nodes()
      |> postprocess_markdown()
    after
      Process.delete({__MODULE__, :skip_classes})
      Process.delete({__MODULE__, :conversion_rules})
    end
  rescue
    e ->
      Logger.warning("HTML to Markdown conversion failed: #{inspect(e)}")
      # Fallback: strip HTML tags
      html |> Floki.parse_document!() |> Floki.text()
  end

  # Preprocess HTML before parsing
  defp preprocess_html(html) do
    html
    |> String.replace(~r/<script[^>]*>.*?<\/script>/is, "")
    |> String.replace(~r/<style[^>]*>.*?<\/style>/is, "")
    |> String.replace(~r/<!--.*?-->/s, "")
  end

  # Process DOM nodes to Markdown
  defp process_nodes(nodes) when is_list(nodes) do
    Enum.map_join(nodes, &process_node/1)
  end

  defp process_nodes(node), do: process_node(node)

  defp process_node(text) when is_binary(text) do
    text
    |> String.replace(~r/\s+/, " ")
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
      "br" -> "\n"
      "hr" -> "\n\n---\n\n"
      # Headings
      "h1" -> "\n\n# #{process_nodes(children)}\n\n"
      "h2" -> "\n\n## #{process_nodes(children)}\n\n"
      "h3" -> "\n\n### #{process_nodes(children)}\n\n"
      "h4" -> "\n\n#### #{process_nodes(children)}\n\n"
      "h5" -> "\n\n##### #{process_nodes(children)}\n\n"
      "h6" -> "\n\n###### #{process_nodes(children)}\n\n"
      # Inline formatting
      "strong" -> "**#{process_nodes(children)}**"
      "b" -> "**#{process_nodes(children)}**"
      "em" -> "*#{process_nodes(children)}*"
      "i" -> "*#{process_nodes(children)}*"
      "code" -> "`#{process_nodes(children)}`"
      "pre" -> "\n\n```\n#{Floki.text(children)}\n```\n\n"
      "mark" -> "==" <> process_nodes(children) <> "=="
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
        process_youtube_div(attrs, children)

      String.contains?(class, "powerpress") ->
        process_powerpress_div(children)

      String.contains?(String.downcase(class), "pullquote") ->
        process_blockquote(children)

      true ->
        process_nodes(children)
    end
  end

  # Process links
  defp process_link(attrs, children) do
    href = get_attr(attrs, "href")

    cond do
      is_nil(href) or href == "" ->
        process_nodes(children) |> String.trim()

      relative_path?(href) ->
        ""

      discard_link?(href) ->
        ""

      true ->
        text = process_nodes(children) |> String.trim()
        clean_href = remove_tracking_params(href)

        if text == "" do
          clean_href
        else
          "[#{text}](#{clean_href})"
        end
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
    |> ImageExtractor.normalize_url()
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

      if caption != "" do
        "\n\n![#{alt}](#{clean_src} \"#{caption}\")\n\n"
      else
        "\n\n![#{alt}](#{clean_src})\n\n"
      end
    else
      ""
    end
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
    lines = content |> String.trim() |> String.split("\n")
    quoted = Enum.map_join(lines, "\n", &("> " <> &1))
    "\n\n#{quoted}\n\n"
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
    src = get_attr(attrs, "src", "")

    cond do
      String.contains?(src, "youtube.com") || String.contains?(src, "youtu.be") ->
        youtube_markdown(src, get_attr(attrs, "title"))

      String.contains?(src, "podbean.com") ->
        process_podbean_iframe(src)

      String.contains?(src, "soundcloud.com") ->
        "\n\n[Listen on SoundCloud](#{src})\n\n"

      true ->
        ""
    end
  end

  defp youtube_markdown(url, title) do
    case Youtube.video_id(url) do
      nil ->
        ""

      video_id ->
        text = Youtube.meaningful_title(title) || "Watch on YouTube"
        "\n\n[#{text}](https://www.youtube.com/watch?v=#{video_id})\n\n"
    end
  end

  defp process_podbean_iframe(src) do
    case Regex.run(~r/i=([^-&]+(?:-[^-&]+)*?)(?:-pb)?(?:&|$)/, src) do
      [_, episode_id] ->
        "\n\n[Listen on Podbean](https://www.podbean.com/ep/pb-#{episode_id})\n\n"

      _ ->
        "\n\n[Listen on Podbean](#{src})\n\n"
    end
  end

  # Process YouTube div with data-attrs
  defp process_youtube_div(attrs, _children) do
    data_attrs = get_attr(attrs, "data-attrs", "")

    if data_attrs != "" do
      case Jason.decode(data_attrs) do
        {:ok, %{"videoId" => video_id} = data} ->
          text =
            Youtube.meaningful_title(data["title"] || data["videoTitle"]) || "Watch on YouTube"

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
      "\n\n[Audio](#{clean_src})\n\n"
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
      "\n\n[Audio](#{clean_src})\n\n"
    else
      ""
    end
  end

  # Process video element
  defp process_video(attrs, children) do
    src = get_attr(attrs, "src") || find_source_src(children)

    if src do
      clean_src = remove_tracking_params(src)
      "\n\n[Video](#{clean_src})\n\n"
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
    # Trailing whitespace
    |> String.replace(~r/[ \t]+\n/, "\n")
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
end
