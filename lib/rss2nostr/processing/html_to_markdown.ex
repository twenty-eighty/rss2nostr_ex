defmodule Rss2Nostr.Processing.HtmlToMarkdown do
  @moduledoc """
  Converts HTML to Markdown with special handling for:
  - Tracking parameter removal from URLs
  - YouTube, SoundCloud, Podbean embeds
  - Responsive images (srcset handling)
  - Figures with captions
  """

  require Logger

  # Tracking parameters to remove from URLs
  @tracking_params ~w(
    _ dmcid fbclid fbc f_tid igshid originalReferrer ref_src
    utm_source utm_medium utm_campaign utm_term utm_content
    wt_zmc xing_share mc_cid mc_eid
  )

  @doc """
  Converts HTML to Markdown.
  """
  @spec convert(String.t() | nil) :: String.t() | nil
  def convert(nil), do: nil
  def convert(""), do: nil

  def convert(html) when is_binary(html) do
    html
    |> preprocess_html()
    |> Floki.parse_document!()
    |> process_nodes()
    |> postprocess_markdown()
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
    case tag do
      # Skip elements
      "script" -> ""
      "style" -> ""
      "nav" -> ""
      "header" -> ""
      "footer" -> ""
      "noscript" -> ""
      # Block elements
      "p" -> "\n\n#{process_nodes(children)}\n\n"
      "div" -> process_div(attrs, children)
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
      "li" -> process_nodes(children)
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
      "section" -> process_nodes(children)
      "main" -> process_nodes(children)
      "aside" -> process_nodes(children)
      # Unknown - process children
      _ -> process_nodes(children)
    end
  end

  defp process_node(_), do: ""

  # Process div with special class handling
  defp process_div(attrs, children) do
    class = get_attr(attrs, "class", "")

    cond do
      String.contains?(class, "youtube") ->
        process_youtube_div(attrs, children)

      String.contains?(class, "powerpress") ->
        process_powerpress_div(children)

      true ->
        process_nodes(children)
    end
  end

  # Process links
  defp process_link(attrs, children) do
    href = get_attr(attrs, "href")
    text = process_nodes(children) |> String.trim()

    if href && href != "" do
      clean_href = remove_tracking_params(href)

      if text == "" do
        clean_href
      else
        "[#{text}](#{clean_href})"
      end
    else
      text
    end
  end

  # Process images
  defp process_image(attrs) do
    src = get_best_image_src(attrs)
    alt = get_attr(attrs, "alt", "")

    if src && src != "" do
      clean_src = clean_image_url(src)
      "![#{alt}](#{clean_src})"
    else
      ""
    end
  end

  # Get best image source (prefer larger images from srcset)
  defp get_best_image_src(attrs) do
    srcset = get_attr(attrs, "srcset") || get_attr(attrs, "data-srcset")
    data_src = get_attr(attrs, "data-src")
    src = get_attr(attrs, "src")

    cond do
      srcset && srcset != "" ->
        parse_srcset(srcset) |> get_largest_image()

      data_src && data_src != "" ->
        data_src

      true ->
        src
    end
  end

  # Parse srcset attribute
  defp parse_srcset(srcset) do
    srcset
    |> String.split(",")
    |> Enum.map(fn entry ->
      parts = String.trim(entry) |> String.split(~r/\s+/)

      case parts do
        [url, size] ->
          width = size |> String.replace(~r/[^\d]/, "") |> String.to_integer()
          {url, width}

        [url] ->
          {url, 0}

        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  rescue
    e ->
      Logger.debug("Failed to parse srcset: #{inspect(e)}")
      []
  end

  defp get_largest_image([]), do: nil

  defp get_largest_image(images) do
    images
    |> Enum.max_by(fn {_url, width} -> width end)
    |> elem(0)
  end

  # Clean image URLs (remove WordPress CDN wrapper, tracking params)
  defp clean_image_url(url) do
    url
    |> remove_wp_cdn_wrapper()
    |> remove_tracking_params()
  end

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
    alt = get_attr(img_attrs, "alt", "")
    caption = if figcaption, do: Floki.text(figcaption) |> String.trim(), else: nil

    if src && src != "" do
      clean_src = clean_image_url(src)
      title = caption || alt

      if title != "" do
        "\n\n![#{alt}](#{clean_src} \"#{title}\")\n\n"
      else
        "\n\n![#{alt}](#{clean_src})\n\n"
      end
    else
      ""
    end
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
        video_id = extract_youtube_id(src)

        if video_id do
          "\n\n[Watch on YouTube](https://www.youtube.com/watch?v=#{video_id})\n\n"
        else
          ""
        end

      String.contains?(src, "podbean.com") ->
        process_podbean_iframe(src)

      String.contains?(src, "soundcloud.com") ->
        "\n\n[Listen on SoundCloud](#{src})\n\n"

      true ->
        ""
    end
  end

  defp extract_youtube_id(url) do
    patterns = [
      ~r/youtube\.com\/embed\/([^?&]+)/,
      ~r/youtube\.com\/watch\?v=([^&]+)/,
      ~r/youtu\.be\/([^?&]+)/
    ]

    Enum.find_value(patterns, fn pattern ->
      case Regex.run(pattern, url) do
        [_, id] -> id
        _ -> nil
      end
    end)
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
        {:ok, %{"videoId" => video_id}} ->
          "\n\n[Watch on YouTube](https://www.youtube.com/watch?v=#{video_id})\n\n"

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
    |> String.trim()
  end

  # Helper: get attribute value
  defp get_attr(attrs, name, default \\ nil) do
    case List.keyfind(attrs, name, 0) do
      {_, value} -> value
      nil -> default
    end
  end

  # Helper: find first element by tag name
  defp find_element(nodes, tag) when is_binary(tag) do
    Enum.find(nodes, fn
      {^tag, _, _} -> true
      _ -> false
    end)
  end

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
