defmodule Rss2Nostr.Processing.BodySchema.Presets do
  @moduledoc false

  @url_schemas [
    {~r/(^|\.)substack\.com$/i, ".body.markup", "Substack article"},
    {~r/(^|\.)heise\.de$/i, "article.akwa-article", "Heise article"},
    {~r/(^|\.)corbettreport\.com$/i, "div.et_pb_column_0_tb_body", "Corbett article"},
    {~r/(^|\.)manova\.news$/i, "div.article-content", "Manova article"},
    {~r/(^|\.)multipolar-magazin\.de$/i, "div.blog-list-content", "Multipolar article"},
    {~r/(^|\.)freie-medienakademie\.de$/i, ".medienplus-article", "Freie Medienakademie article"}
  ]

  @page_builders [
    {".vc_column-inner > .wpb_wrapper", "WPBakery column"},
    {"div.wpb_wrapper", "WPBakery wrapper"},
    {"div.wpb_text_column", "WPBakery text"},
    {".elementor-widget-theme-post-content", "Elementor post content"},
    {".et_pb_post_content", "Divi post content"},
    {".fl-post-content", "Beaver Builder post"},
    {".wp-block-post-content", "Gutenberg post content"}
  ]

  @preset_labels Map.merge(
                   %{
                     "div.entry-content" => "WordPress article",
                     "article.akwa-article" => "Heise article",
                     "article" => "HTML article element",
                     "div.et_pb_column_0_tb_body" => "Corbett article",
                     "div.article-content" => "Manova article",
                     "div.blog-list-content" => "Multipolar article",
                     ".medienplus-article" => "Freie Medienakademie article",
                     ".body.markup" => "Substack article",
                     ".post-content" => "Blog post content",
                     ".post_content" => "Blog post content",
                     "[itemprop='articleBody']" => "Article body",
                     "main" => "HTML main element"
                   },
                   Map.new(@page_builders)
                 )

  @page_builder_selectors Enum.map(@page_builders, &elem(&1, 0))

  @article_selectors [
    "div.entry-content",
    ".wp-block-post-content",
    ".post-content",
    ".post_content",
    "[itemprop='articleBody']",
    "div.article-content",
    "article"
  ]

  @type schema :: %{selector: String.t(), label: String.t()}

  @spec preset_labels() :: map()
  def preset_labels, do: @preset_labels

  @spec page_builder_selectors() :: [String.t()]
  def page_builder_selectors, do: @page_builder_selectors

  @spec article_selectors() :: [String.t()]
  def article_selectors, do: @article_selectors

  @spec schema_for_url(String.t() | nil) :: schema() | nil
  def schema_for_url(url) when is_binary(url) do
    host = url |> URI.parse() |> Map.get(:host) |> to_string()

    Enum.find_value(@url_schemas, fn {pattern, selector, label} ->
      if Regex.match?(pattern, host) do
        %{selector: selector, label: label}
      end
    end)
  rescue
    _ -> nil
  end

  def schema_for_url(_), do: nil

  @spec selector_for_url(String.t() | nil) :: String.t() | nil
  def selector_for_url(url) do
    case schema_for_url(url) do
      %{selector: selector} -> selector
      _ -> nil
    end
  end

  @spec known_selector?(String.t() | nil) :: boolean()
  def known_selector?(selector) when is_binary(selector) do
    selector = String.trim(selector)
    selector != "" and Map.has_key?(@preset_labels, selector)
  end

  def known_selector?(_), do: false

  @spec known_selectors() :: [String.t()]
  def known_selectors, do: Map.keys(@preset_labels)

  @spec label_for(String.t()) :: String.t()
  def label_for(selector) do
    Map.get(@preset_labels, selector) ||
      case Regex.run(~r/^[a-z0-9]+\.([A-Za-z0-9_-]+)$/i, selector) do
        [_, class] -> class
        _ -> selector
      end
  end
end
