defmodule Rss2Nostr.Processing.HtmlToMarkdown.Images do
  @moduledoc false

  require Logger

  alias Rss2Nostr.Processing.ImageExtractor
  alias Rss2Nostr.Processing.HtmlToMarkdown.{Dom, TrackingParams}

  @type process_nodes :: (list() -> String.t())

  @spec process_image(list()) :: String.t()
  def process_image(attrs) do
    if tracking_pixel?(attrs) do
      ""
    else
      src = get_best_image_src(attrs)
      alt = image_alt(attrs)

      if src && src != "" do
        "![#{alt}](#{src})"
      else
        ""
      end
    end
  end

  @doc false
  @spec tracking_pixel?(term()) :: boolean()
  def tracking_pixel?(attrs) when is_list(attrs) do
    tracking_pixel_marker?(attrs) or tracking_pixel_src?(attrs) or one_by_one_pixel?(attrs)
  end

  def tracking_pixel?(_), do: false

  @doc false
  @spec tracking_wrapper?(term()) :: boolean()
  def tracking_wrapper?(attrs) when is_list(attrs), do: tracking_pixel_marker?(attrs)
  def tracking_wrapper?(_), do: false

  @spec process_figure(list(), list(), process_nodes()) :: String.t()
  def process_figure(_attrs, children, process_nodes) do
    img = Dom.find_element(children, "img")
    figcaption = Dom.find_element(children, "figcaption")

    img_attrs =
      case img do
        {_, attrs, _} -> attrs
        _ -> []
      end

    src = get_best_image_src(img_attrs)
    alt = image_alt(img_attrs)
    caption = figcaption_text(figcaption)

    cond do
      tracking_pixel?(img_attrs) ->
        ""

      src && src != "" ->
        clean_src = clean_image_url(src)

        image_md =
          if caption != "" do
            ~s|![#{alt}](#{clean_src} "#{escape_md_title(caption)}")|
          else
            "![#{alt}](#{clean_src})"
          end

        case figure_wrap_href(children, img_attrs, clean_src) do
          href when is_binary(href) -> "\n\n[#{image_md}](#{href})\n\n"
          _ -> "\n\n#{image_md}\n\n"
        end

      true ->
        process_nodes.(children)
    end
  end

  @spec process_picture(list()) :: String.t()
  def process_picture(children) do
    source = Dom.find_element(children, "source")
    img = Dom.find_element(children, "img")

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

  @spec get_best_image_src(list()) :: String.t() | nil
  defp get_best_image_src(attrs) do
    srcset = Dom.get_attr(attrs, "srcset") || Dom.get_attr(attrs, "data-srcset")

    [
      srcset && srcset != "" && get_largest_image(parse_srcset(srcset)),
      Dom.get_attr(attrs, "data-src"),
      Dom.get_attr(attrs, "src")
    ]
    |> Enum.find_value(fn
      url when is_binary(url) and url != "" ->
        cleaned = clean_image_url(url)
        if http_url?(cleaned), do: cleaned

      _ ->
        nil
    end)
  end

  @spec parse_srcset(String.t()) :: [{String.t(), integer()}]
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

  @spec parse_srcset_entry(String.t()) :: {String.t(), integer()} | nil
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

  @spec usable_srcset_url?(String.t()) :: boolean()
  defp usable_srcset_url?(url) do
    String.starts_with?(url, ["http://", "https://", "//"])
  end

  @spec get_largest_image([{String.t(), integer()}]) :: String.t() | nil
  defp get_largest_image([]), do: nil

  defp get_largest_image(images) do
    images
    |> Enum.max_by(fn {_url, width} -> width end)
    |> elem(0)
  end

  @spec clean_image_url(String.t()) :: String.t()
  defp clean_image_url(url) do
    url
    |> remove_wp_cdn_wrapper()
    |> ImageExtractor.display_url()
    |> TrackingParams.remove()
  end

  @spec http_url?(String.t()) :: boolean()
  defp http_url?(url) when is_binary(url) do
    uri = URI.parse(url)
    uri.scheme in ["http", "https"] and is_binary(uri.host) and uri.host != ""
  rescue
    _ -> false
  end

  @spec remove_wp_cdn_wrapper(String.t()) :: String.t()
  defp remove_wp_cdn_wrapper(url) do
    case Regex.run(~r/https?:\/\/i\d\.wp\.com\/(.+)/, url) do
      [_, inner_url] -> "https://#{inner_url}"
      _ -> url
    end
  end

  @spec figure_wrap_href(list(), list(), String.t()) :: String.t() | nil
  defp figure_wrap_href(children, img_attrs, image_src) do
    href =
      case Dom.find_element(children, "a") do
        {"a", attrs, _} -> Dom.get_attr(attrs, "href")
        _ -> nil
      end

    href = href || href_from_data_attrs(img_attrs)
    keep_figure_href(href, image_src)
  end

  @spec href_from_data_attrs(list()) :: String.t() | nil
  defp href_from_data_attrs(attrs) do
    case Dom.get_attr(attrs, "data-attrs") do
      json when is_binary(json) and json != "" ->
        case Jason.decode(json) do
          {:ok, %{"href" => href}} when is_binary(href) and href != "" -> href
          _ -> nil
        end

      _ ->
        nil
    end
  end

  @spec keep_figure_href(term(), term()) :: String.t() | nil
  defp keep_figure_href(href, image_src) when is_binary(href) and href != "" do
    cond do
      relative_path?(href) or discard_link?(href) or not http_url?(href) ->
        nil

      same_image_ref?(href, image_src) or image_like_href?(href) ->
        nil

      true ->
        TrackingParams.remove(href)
    end
  end

  defp keep_figure_href(_, _), do: nil

  @spec same_image_ref?(String.t(), String.t()) :: boolean()
  defp same_image_ref?(left, right) do
    a = ImageExtractor.normalize_url(left)
    b = ImageExtractor.normalize_url(right)

    a != "" and b != "" and
      (a == b or Path.basename(a) == Path.basename(b))
  end

  @spec image_like_href?(String.t()) :: boolean()
  defp image_like_href?(href) do
    path = href |> URI.parse() |> Map.get(:path, "") |> to_string() |> String.downcase()
    ext = path |> Path.extname() |> String.trim_leading(".")

    ext in ~w(jpg jpeg png gif webp heic heif svg avif) or
      String.contains?(path, "/image/fetch/")
  rescue
    _ -> false
  end

  @spec image_alt(list()) :: String.t()
  defp image_alt(attrs) do
    case Dom.get_attr(attrs, "alt", "") do
      value when value in [nil, "", "alt"] -> ""
      value -> value
    end
  end

  @spec figcaption_text(term()) :: String.t()
  defp figcaption_text(nil), do: ""

  defp figcaption_text(figcaption) do
    figcaption |> Floki.text() |> String.trim()
  end

  @spec escape_md_title(String.t()) :: String.t()
  defp escape_md_title(title), do: String.replace(title, "\"", "'")

  @spec relative_path?(String.t()) :: boolean()
  defp relative_path?(href) do
    String.starts_with?(href, "/") and not String.starts_with?(href, "//")
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

  @spec tracking_pixel_marker?(list()) :: boolean()
  defp tracking_pixel_marker?(attrs) do
    haystack =
      [Dom.get_attr(attrs, "id", ""), Dom.get_attr(attrs, "class", "")]
      |> Enum.map(&to_string/1)
      |> Enum.join(" ")
      |> String.downcase()

    String.contains?(haystack, "wp-worthy-pixel") or
      String.contains?(haystack, "worthy-pixel")
  end

  @spec tracking_pixel_src?(list()) :: boolean()
  defp tracking_pixel_src?(attrs) do
    [Dom.get_attr(attrs, "src"), Dom.get_attr(attrs, "data-src")]
    |> Enum.any?(&ImageExtractor.Urls.tracking_pixel?/1)
  end

  @spec one_by_one_pixel?(list()) :: boolean()
  defp one_by_one_pixel?(attrs) do
    parse_px(Dom.get_attr(attrs, "width")) == 1 and
      parse_px(Dom.get_attr(attrs, "height")) == 1
  end

  @spec parse_px(term()) :: integer() | nil
  defp parse_px(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_px(_), do: nil
end
