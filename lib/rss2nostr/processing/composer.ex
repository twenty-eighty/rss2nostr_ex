defmodule Rss2Nostr.Processing.Composer do
  @moduledoc """
  Builds the Markdown that becomes a NIP-23 event from either feed XML
  or the article page, using per-source composition settings.
  """

  alias Rss2Nostr.Import.{FeedFetcher, ItemIdentity}

  alias Rss2Nostr.Processing.{
    BodySchema,
    Conversion,
    HtmlToMarkdown,
    Sites,
    Soundcloud,
    Youtube
  }

  alias Rss2Nostr.Import.FeedParser
  alias Rss2Nostr.Nostr.Event

  alias Rss2Nostr.Processing.Composer.{
    FeaturedImage,
    FeedItem,
    FeedPreview,
    PageMeta
  }

  alias Rss2Nostr.Sources.Source

  @body_presets [
    {"Custom", ""},
    {"WordPress (entry-content)", "div.entry-content"},
    {"Heise (akwa-article)", "article.akwa-article"},
    {"Heise (article)", "article"},
    {"Corbett (Divi column)", "div.et_pb_column_0_tb_body"},
    {"Manova", "div.article-content"},
    {"Multipolar", "div.blog-list-content"},
    {"Freie Medienakademie", ".medienplus-article"},
    {"Substack (body markup)", ".body.markup"},
    {"Generic post-content", ".post-content"},
    {"HTML main", "main"},
    {"Article body (itemprop)", "[itemprop='articleBody']"},
    {"WPBakery column", ".vc_column-inner > .wpb_wrapper"},
    {"WPBakery wrapper", "div.wpb_wrapper"},
    {"WPBakery text", "div.wpb_text_column"},
    {"Elementor post content", ".elementor-widget-theme-post-content"},
    {"Divi post content", ".et_pb_post_content"},
    {"Beaver Builder post", ".fl-post-content"},
    {"Gutenberg post content", ".wp-block-post-content"}
  ]

  @type compose_opts :: %{
          optional(:fetch_source_from) => String.t(),
          optional(:body_selector) => String.t() | nil,
          optional(:start_at) => String.t() | nil,
          optional(:skip_classes) => [String.t()],
          optional(:conversion_rules) => [map()],
          optional(:url) => String.t() | nil,
          optional(:body_selector_auto) => boolean(),
          optional(:title) => String.t() | nil,
          optional(:image) => String.t() | nil,
          optional(:summary) => String.t() | nil,
          optional(:language) => String.t() | nil,
          optional(:fetch_page_image) => boolean(),
          optional(:soundcloud_artwork) => (String.t() -> String.t() | nil) | false | nil
        }

  @type compose_result :: %{
          markdown: String.t(),
          html: String.t(),
          selector_matched: boolean(),
          title: String.t() | nil,
          image: String.t() | nil,
          summary: String.t() | nil,
          link_groups: [Conversion.link_group()],
          body_regions: [map()],
          start_blocks: [map()]
        }

  @type preview_part :: %{
          index: pos_integer(),
          total: pos_integer(),
          markdown: String.t(),
          html: String.t()
        }

  @type preview_context :: %{
          url: String.t() | nil,
          guid: String.t() | nil,
          source: Source.t() | nil,
          opts: compose_opts(),
          params: map(),
          rules: [map()],
          language: String.t() | nil
        }

  @type preview_result :: %{
          title: term(),
          summary: String.t() | nil,
          image: String.t() | nil,
          markdown: String.t() | nil,
          html: String.t(),
          html_source: String.t(),
          selector_matched: boolean(),
          guid: term(),
          link: term(),
          link_groups: [map()],
          body_selector: String.t(),
          start_at: String.t() | nil,
          body_regions: list(),
          start_blocks: [map()],
          nostr_event: map(),
          nostr_event_json: String.t(),
          hashtags: [String.t()],
          nostr_parts: [map()],
          nostr_parts_json: [String.t()],
          nostr_parts_preview: [map()],
          nostr_inner: nil,
          nostr_inner_json: nil,
          nostr_encrypted: false,
          nostr_draft: boolean(),
          nostr_plain_draft: boolean(),
          nostr_relays: [String.t()]
        }

  @spec body_presets() :: [{String.t(), String.t()}]
  def body_presets, do: @body_presets

  @spec default_skip_classes() :: [String.t()]
  def default_skip_classes, do: HtmlToMarkdown.default_skip_classes()

  @spec default_skip_classes_text() :: String.t()
  def default_skip_classes_text, do: Enum.join(default_skip_classes(), ", ")

  @spec parse_skip_classes(term()) :: [String.t()]
  def parse_skip_classes(nil), do: default_skip_classes()
  def parse_skip_classes(""), do: []

  def parse_skip_classes(list) when is_list(list) do
    list
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  def parse_skip_classes(text) when is_binary(text) do
    text
    |> String.split(~r/[\n,]+/)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  def parse_skip_classes(_), do: default_skip_classes()

  @spec opts_from_source(Source.t() | nil) :: compose_opts()
  def opts_from_source(nil) do
    %{
      fetch_source_from: "fetch_from_url",
      body_selector: nil,
      start_at: nil,
      skip_classes: default_skip_classes(),
      conversion_rules: [],
      url: nil,
      language: nil
    }
  end

  def opts_from_source(%Source{} = source) do
    options = source.options || %{}

    %{
      fetch_source_from: source.fetch_source_from || "fetch_from_url",
      body_selector: blank_to_nil(options["body_selector"] || options[:body_selector]),
      start_at: blank_to_nil(options["start_at"] || options[:start_at]),
      skip_classes: parse_skip_classes(options["skip_classes"] || options[:skip_classes]),
      conversion_rules:
        Conversion.parse_rules(options["conversion_rules"] || options[:conversion_rules]),
      url: blank_to_nil(source.url),
      language: blank_to_nil(source.language)
    }
  end

  @spec opts_from_params(map()) :: compose_opts()
  def opts_from_params(params) when is_map(params) do
    %{
      fetch_source_from: fetch_mode(params),
      body_selector: blank_to_nil(params["body_selector"] || params[:body_selector]),
      start_at: blank_to_nil(params["start_at"] || params[:start_at]),
      skip_classes: parse_skip_classes(params["skip_classes"] || params[:skip_classes]),
      conversion_rules:
        Conversion.parse_rules(params["conversion_rules"] || params[:conversion_rules]),
      url: blank_to_nil(params["url"] || params[:url]),
      language: blank_to_nil(params["language"] || params[:language])
    }
  end

  @doc """
  Resolves the HTML that should be converted for a feed item.
  """
  @spec html_for_item(FeedParser.feed_item() | map(), Source.t() | compose_opts() | map()) ::
          {:ok, String.t(), String.t()} | {:error, String.t()}
  def html_for_item(item, source_or_opts) do
    opts = normalize_opts(source_or_opts)
    feed_html = FeedItem.html(item)
    mode = opts.fetch_source_from

    page = ItemIdentity.page_url(item)

    result =
      cond do
        is_binary(page) and (mode == "fetch_from_url" or blank?(feed_html)) ->
          case FeedFetcher.fetch_article(page) do
            {:ok, html} -> {:ok, html, "url"}
            {:error, reason} -> {:error, reason}
          end

        not blank?(feed_html) ->
          {:ok, feed_html, "feed"}

        true ->
          {:error, "Article has no URL or feed content"}
      end

    FeedItem.with_enclosure_html(result, item, opts.language)
  end

  @doc """
  Extracts the article body with an optional CSS selector.
  Returns `{html, matched?}`.
  """
  @spec extract_body(String.t() | nil, String.t() | nil) :: {String.t() | nil, boolean()}
  def extract_body(html, _selector) when html in [nil, ""], do: {html, false}
  def extract_body(html, selector) when selector in [nil, ""], do: {html, false}

  def extract_body(html, selector) when is_binary(html) and is_binary(selector) do
    case BodySchema.extract(html, selector) do
      nil -> {html, false}
      extracted -> {extracted, true}
    end
  end

  @spec extract_meta(String.t() | nil) :: PageMeta.meta()
  def extract_meta(html), do: PageMeta.extract(html)

  @spec compose(String.t() | nil, compose_opts() | keyword() | map()) :: compose_result()
  def compose(html, opts \\ %{}) do
    opts = normalize_opts(opts)
    selector = resolve_body_selector(opts, html)
    meta = PageMeta.extract(html)
    # Prefer page og:image over feed media:content — some CDNs (e.g. website-editor)
    # only serve signed page URLs and 403 the bare feed URL in the browser.
    image = meta.image || PageMeta.page_featured_image(html, opts) || opts.image
    {body, matched} = extract_body(html, selector)
    body = BodySchema.apply_start_at(body, opts.start_at)
    body = FeaturedImage.drop_opening_featured_html(body, image)

    body =
      Sites.preprocess(body,
        url: opts.url,
        body_selector: selector
      )

    rules = opts.conversion_rules

    markdown =
      body
      |> HtmlToMarkdown.convert(
        skip_classes: opts.skip_classes,
        conversion_rules: rules,
        language: opts.language
      )
      |> Youtube.enrich_markdown()

    {image, markdown} = FeaturedImage.promote_leading_image(markdown, image)
    image = blank_to_nil(image) || soundcloud_artwork(body || html, opts)

    %{
      markdown: markdown,
      html: render_html(markdown),
      selector_matched: matched,
      title: opts.title || meta.title,
      image: image,
      summary: HtmlToMarkdown.plain_summary(opts.summary || meta.summary),
      link_groups: Conversion.candidates(body, rules),
      body_regions: [],
      start_blocks: []
    }
  end

  @doc """
  Renders Markdown to HTML for the compose preview.
  """
  @spec render_html(String.t() | nil) :: String.t()
  def render_html(nil), do: ""
  def render_html(""), do: ""

  def render_html(markdown) when is_binary(markdown) do
    Rss2Nostr.Processing.Markdown.to_html(markdown)
  end

  @doc """
  Preview payload for each split Nostr part (markdown + rendered HTML).
  """
  @spec preview_parts([Event.unsigned_event() | map()]) :: [preview_part()]
  def preview_parts(parts) when is_list(parts) do
    total = length(parts)

    parts
    |> Enum.with_index(1)
    |> Enum.map(fn {event, index} ->
      content = event[:content] || event["content"] || ""

      %{
        index: index,
        total: total,
        markdown: content,
        html: render_html(content)
      }
    end)
  end

  @doc """
  Fetches a feed article and returns a Markdown preview of the Nostr event.
  """
  @spec preview(map()) :: {:ok, preview_result()} | {:error, String.t()}
  def preview(params) when is_map(params), do: FeedPreview.preview(params)

  @spec normalize_opts(Source.t() | keyword() | map()) :: compose_opts()
  defp normalize_opts(%Source{} = source), do: opts_from_source(source)

  defp normalize_opts(opts) when is_list(opts) do
    normalize_opts(Map.new(opts))
  end

  defp normalize_opts(opts) when is_map(opts) do
    %{
      fetch_source_from: fetch_mode(opts),
      body_selector: blank_to_nil(opts[:body_selector] || opts["body_selector"]),
      start_at: blank_to_nil(opts[:start_at] || opts["start_at"]),
      skip_classes: parse_skip_classes(opts[:skip_classes] || opts["skip_classes"]),
      conversion_rules:
        Conversion.parse_rules(opts[:conversion_rules] || opts["conversion_rules"]),
      url: blank_to_nil(opts[:url] || opts["url"]),
      body_selector_auto: body_selector_auto?(opts),
      title: opts[:title] || opts["title"],
      image: opts[:image] || opts["image"],
      summary: opts[:summary] || opts["summary"],
      language: blank_to_nil(opts[:language] || opts["language"]),
      fetch_page_image: opts[:fetch_page_image] == true or opts["fetch_page_image"] == true,
      soundcloud_artwork: Map.get(opts, :soundcloud_artwork, Map.get(opts, "soundcloud_artwork"))
    }
  end

  @spec fetch_mode(Source.t() | map() | String.t() | nil) :: String.t()
  defp fetch_mode(%Source{fetch_source_from: mode}), do: fetch_mode(mode)

  defp fetch_mode(opts) when is_map(opts) do
    fetch_mode(opts[:fetch_source_from] || opts["fetch_source_from"])
  end

  defp fetch_mode("content"), do: "content"
  defp fetch_mode(_), do: "fetch_from_url"

  @spec resolve_body_selector(compose_opts(), String.t() | nil) :: String.t() | nil
  defp resolve_body_selector(opts, html) do
    cond do
      is_binary(opts.body_selector) and opts.body_selector != "" ->
        opts.body_selector

      opts.body_selector_auto == false ->
        nil

      true ->
        BodySchema.preferred_selector(html, opts.url)
    end
  end

  @spec body_selector_auto?(map()) :: boolean()
  defp body_selector_auto?(opts) when is_map(opts) do
    auto_body_selector?(opts)
  end

  @spec auto_body_selector?(map()) :: boolean()
  defp auto_body_selector?(params) do
    case params["body_selector_auto"] || params[:body_selector_auto] do
      value when value in [true, "true", "1", "on", "yes"] -> true
      value when value in [false, "false", "0", "off", "no"] -> false
      _ -> true
    end
  end

  @spec soundcloud_artwork(String.t() | nil, compose_opts()) :: String.t() | nil
  defp soundcloud_artwork(_html, %{soundcloud_artwork: false}), do: nil

  defp soundcloud_artwork(html, opts) do
    permalink = HtmlToMarkdown.soundcloud_permalink(html)

    case Map.get(opts, :soundcloud_artwork) do
      fun when is_function(fun, 1) ->
        if permalink, do: fun.(permalink)

      _ ->
        Soundcloud.artwork_url(permalink)
    end
  end

  @spec blank?(term()) :: boolean()
  defp blank?(value), do: blank_to_nil(value) == nil

  @spec blank_to_nil(term()) :: term()
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
