defmodule Rss2Nostr.Processing.Composer.PageMeta do
  @moduledoc false

  alias Rss2Nostr.Import.FeedFetcher
  alias Rss2Nostr.Processing.Composer.FeaturedImage

  @type meta :: %{
          title: String.t() | nil,
          image: String.t() | nil,
          summary: String.t() | nil
        }

  @spec extract(String.t() | nil) :: meta()
  def extract(html) when html in [nil, ""], do: %{title: nil, image: nil, summary: nil}

  def extract(html) when is_binary(html) do
    case Floki.parse_document(html) do
      {:ok, doc} ->
        %{
          title: meta_content(doc, "meta[property='og:title']") || document_title(doc),
          image:
            meta_content(doc, "meta[property='og:image']") ||
              meta_content(doc, "meta[property='og:image:url']") ||
              meta_content(doc, "meta[name='twitter:image']") ||
              meta_content(doc, "meta[name='twitter:image:src']") ||
              meta_content(doc, "meta[property='twitter:image']") ||
              link_href(doc, "link[rel='image_src']") ||
              first_featured_img(doc, "img.wp-post-image") ||
              first_featured_img(doc, "figure.wp-block-post-featured-image img") ||
              first_featured_img(doc, "img[itemprop='image']"),
          summary:
            meta_content(doc, "meta[name='description']") ||
              meta_content(doc, "meta[property='og:description']")
        }

      _ ->
        %{title: nil, image: nil, summary: nil}
    end
  end

  @spec page_featured_image(String.t() | nil, map()) :: String.t() | nil
  def page_featured_image(html, opts) do
    url = opts.url

    cond do
      Map.get(opts, :fetch_page_image) != true ->
        nil

      not is_binary(url) or url == "" ->
        nil

      full_html_document?(html) ->
        nil

      true ->
        case FeedFetcher.fetch_article(url) do
          {:ok, page} -> extract(page).image
          _ -> nil
        end
    end
  end

  defp meta_content(doc, selector) do
    doc
    |> Floki.find(selector)
    |> Floki.attribute("content")
    |> List.first()
    |> blank_to_nil()
  end

  defp link_href(doc, selector) do
    doc
    |> Floki.find(selector)
    |> Floki.attribute("href")
    |> List.first()
    |> blank_to_nil()
  end

  defp first_featured_img(doc, selector) do
    doc
    |> Floki.find(selector)
    |> Enum.find_value(fn {_, attrs, _} = node ->
      if featured_img_node?(node) do
        attrs |> FeaturedImage.img_attr_urls() |> List.first() |> blank_to_nil()
      end
    end)
  end

  defp featured_img_node?({_, attrs, _}) do
    class = html_attr_value(attrs, "class") || ""
    width = parse_px(html_attr_value(attrs, "width"))
    height = parse_px(html_attr_value(attrs, "height"))

    not String.match?(class, ~r/\b(thumb|small|avatar|emoji)\b/i) and
      (is_nil(width) or width >= 50) and
      (is_nil(height) or height >= 50)
  end

  defp html_attr_value(attrs, name) do
    case List.keyfind(attrs, name, 0) do
      {_, value} -> value
      nil -> nil
    end
  end

  defp parse_px(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_px(_), do: nil

  defp full_html_document?(html) when is_binary(html), do: String.match?(html, ~r/<html[\s>]/i)
  defp full_html_document?(_), do: false

  defp document_title(doc) do
    doc
    |> Floki.find("title")
    |> Floki.text()
    |> String.trim()
    |> blank_to_nil()
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value
end
