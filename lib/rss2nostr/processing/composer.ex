defmodule Rss2Nostr.Processing.Composer do
  @moduledoc """
  Builds the Markdown that becomes a NIP-23 event from either feed XML
  or the article page, using per-source composition settings.
  """

  alias Rss2Nostr.Import.{FeedFetcher, FeedParser, ItemIdentity}
  alias Rss2Nostr.Nostr.Publisher

  alias Rss2Nostr.Processing.{
    BodySchema,
    Conversion,
    HtmlToMarkdown,
    ImageExtractor,
    Labels,
    Sites,
    Soundcloud,
    Youtube
  }

  alias Rss2Nostr.Sources
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
  @spec html_for_item(map(), Source.t() | compose_opts() | map()) ::
          {:ok, String.t(), String.t()} | {:error, String.t()}
  def html_for_item(item, source_or_opts) do
    opts = normalize_opts(source_or_opts)
    feed_html = item_html(item)
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

    with_enclosure_html(result, item, opts.language)
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

  @spec extract_meta(String.t() | nil) :: %{
          title: String.t() | nil,
          image: String.t() | nil,
          summary: String.t() | nil
        }
  def extract_meta(html) when html in [nil, ""] do
    %{title: nil, image: nil, summary: nil}
  end

  def extract_meta(html) when is_binary(html) do
    case Floki.parse_document(html) do
      {:ok, doc} ->
        %{
          title: meta_content(doc, "meta[property='og:title']") || document_title(doc),
          image: meta_content(doc, "meta[property='og:image']") ||
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

  @spec compose(String.t() | nil, compose_opts() | keyword() | map()) :: map()
  def compose(html, opts \\ %{}) do
    opts = normalize_opts(opts)
    selector = resolve_body_selector(opts, html)
    meta = extract_meta(html)
    image = opts.image || meta.image || page_featured_image(html, opts)
    {body, matched} = extract_body(html, selector)
    body = BodySchema.apply_start_at(body, opts.start_at)
    body = drop_opening_featured_html(body, image)

    body =
      Sites.preprocess(body,
        url: opts.url,
        body_selector: selector
      )

    rules = opts.conversion_rules || []

    markdown =
      body
      |> HtmlToMarkdown.convert(
        skip_classes: opts.skip_classes,
        conversion_rules: rules,
        language: opts.language
      )
      |> Youtube.enrich_markdown()

    {image, markdown} = maybe_promote_leading_image(markdown, image)
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
  @spec preview_parts([map()]) :: [map()]
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
  @spec preview(map()) :: {:ok, map()} | {:error, String.t()}
  def preview(params) when is_map(params) do
    url = params["url"] || params[:url]
    guid = params["guid"] || params[:guid]
    source = load_source(params)
    opts = opts_from_params(params)
    language = preview_language(params, source)
    opts = Map.put(opts, :language, language)
    rules = preview_conversion_rules(params, source, opts)

    with {:ok, body} <- fetch_feed(url),
         type <- FeedParser.detect_feed_type(body) || params["type"] || params[:type],
         {:ok, items} <- parse_items(body, type),
         {:ok, item} <- find_item(items, guid) do
      case html_for_item(item, opts) do
        {:ok, html, html_source} ->
          article_url =
            ItemIdentity.page_url(item) || item_field(item, :enclosure_url) ||
              item_field(item, :link) || url
          selector = preview_selector(opts, params, article_url, html)

          composed =
            compose(html, %{
              body_selector: selector,
              body_selector_auto: auto_body_selector?(params),
              start_at: opts.start_at,
              skip_classes: opts.skip_classes,
              conversion_rules: rules,
              url: article_url,
              title: item_field(item, :title),
              image: item_field(item, :image),
              summary: truncate_summary(HtmlToMarkdown.plain_summary(item_field(item, :summary))),
              language: language,
              fetch_page_image: true
            })

          {extracted, _} = extract_body(html, selector)

          nostr =
            Publisher.preview_event(
              %{
                title: composed.title,
                content: composed.markdown,
                summary: composed.summary,
                image: composed.image,
                source_url: article_url,
                published_at: item_field(item, :published_at),
                language: language || (source && source.language),
                categories: item_field(item, :categories) || [],
                type: source && source.default_post_kind,
                pubkey: source && source.pubkey
              },
              source: source
            )

          {:ok,
           %{
             title: composed.title,
             summary: composed.summary,
             image: composed.image,
             markdown: composed.markdown,
             html: composed.html,
             html_source: html_source,
             selector_matched: composed.selector_matched,
             guid: item_field(item, :guid),
             link: item_field(item, :link),
             link_groups: composed.link_groups,
             body_selector: selector || "",
             start_at: opts.start_at,
             body_regions:
               BodySchema.candidates(html, url: article_url, selected: selector || ""),
             start_blocks: BodySchema.start_blocks(extracted, selected: opts.start_at),
             nostr_event: nostr.event,
             nostr_event_json: nostr.json,
             nostr_parts: nostr.parts,
             nostr_parts_json:
               Enum.map(nostr.parts, fn event ->
                 Jason.encode!(["EVENT", event], pretty: true)
               end),
             nostr_parts_preview: preview_parts(nostr.parts),
             nostr_inner: nil,
             nostr_inner_json: nil,
             nostr_encrypted: false,
             nostr_draft: nostr.draft,
             nostr_plain_draft: nostr.plain_draft,
             nostr_relays: nostr.relays
           }}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp preview_conversion_rules(params, source, opts) do
    if Map.has_key?(params, "conversion_rules") or Map.has_key?(params, :conversion_rules) do
      opts.conversion_rules
    else
      source
      |> opts_from_source()
      |> Map.get(:conversion_rules, [])
    end
  end

  defp load_source(params) do
    id = params["source_id"] || params[:source_id]

    cond do
      match?(%Source{}, id) ->
        id

      is_integer(id) ->
        Sources.get_source(id)

      is_binary(id) ->
        case Integer.parse(id) do
          {int, ""} -> Sources.get_source(int)
          _ -> nil
        end

      true ->
        nil
    end
  end

  defp fetch_feed(url) when is_binary(url) and url != "" do
    FeedFetcher.fetch(url)
  end

  defp fetch_feed(_), do: {:error, "Feed URL is required"}

  defp parse_items(_body, nil), do: {:error, "Not an RSS or Atom feed"}

  defp parse_items(body, type) do
    case FeedParser.parse(body, type) do
      {:ok, []} -> {:error, "Feed has no articles"}
      {:ok, items} -> {:ok, items}
      {:error, reason} -> {:error, reason}
    end
  end

  defp find_item([first | _], guid) when guid in [nil, ""], do: {:ok, first}

  defp find_item(items, guid) do
    case Enum.find(items, fn item ->
           item_field(item, :guid) == guid or item_field(item, :link) == guid
         end) do
      nil -> {:error, "Article not found in feed"}
      item -> {:ok, item}
    end
  end

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

  defp fetch_mode(%Source{fetch_source_from: mode}), do: fetch_mode(mode)

  defp fetch_mode(opts) when is_map(opts) do
    fetch_mode(opts[:fetch_source_from] || opts["fetch_source_from"])
  end

  defp fetch_mode("content"), do: "content"
  defp fetch_mode(_), do: "fetch_from_url"

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

  defp body_selector_auto?(opts) when is_map(opts) do
    auto_body_selector?(opts)
  end

  defp preview_language(params, source) do
    blank_to_nil(params["language"] || params[:language]) ||
      (source && blank_to_nil(source.language))
  end

  defp preview_selector(opts, params, article_url, html) do
    cond do
      is_binary(opts.body_selector) and opts.body_selector != "" ->
        opts.body_selector

      auto_body_selector?(params) ->
        BodySchema.preferred_selector(html, article_url)

      true ->
        nil
    end
  end

  defp auto_body_selector?(params) do
    case params["body_selector_auto"] || params[:body_selector_auto] do
      value when value in [true, "true", "1", "on", "yes"] -> true
      value when value in [false, "false", "0", "off", "no"] -> false
      _ -> true
    end
  end

  defp with_enclosure_html({:ok, html, source}, item, language) do
    {:ok, enclosure_prefix(item, html, language) <> to_string(html || ""), source}
  end

  defp with_enclosure_html(other, _item, _language), do: other

  defp enclosure_prefix(item, html, language) do
    url = item_field(item, :enclosure_url)
    html = to_string(html || "")

    cond do
      ItemIdentity.page_url(item) ->
        ""

      blank?(url) ->
        ""

      String.contains?(html, url) ->
        ""

      ImageExtractor.video_url?(url) ->
        title = enclosure_title(item)
        title_attr = if title, do: ~s( title="#{html_attr(title)}"), else: ""
        ~s(<p><a href="#{html_attr(url)}"#{title_attr}>#{Labels.t(:video, language)}</a></p>\n)

      ImageExtractor.audio_url?(url) ->
        title = enclosure_title(item)
        title_attr = if title, do: ~s( title="#{html_attr(title)}"), else: ""
        ~s(<p><a href="#{html_attr(url)}"#{title_attr}>#{Labels.t(:audio, language)}</a></p>\n)

      true ->
        ""
    end
  end

  defp enclosure_title(item) do
    parts =
      [item_field(item, :duration), item_field(item, :enclosure_length)]
      |> Enum.map(&to_string_or_nil/1)
      |> Enum.reject(&is_nil/1)

    if parts == [], do: nil, else: Enum.join(parts, " ")
  end

  defp to_string_or_nil(value) when is_integer(value) and value > 0, do: Integer.to_string(value)
  defp to_string_or_nil(value) when is_binary(value) and value != "", do: value
  defp to_string_or_nil(_), do: nil

  defp html_attr(value) when is_binary(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("\"", "&quot;")
    |> String.replace("<", "&lt;")
  end

  defp item_html(item) do
    content = item_field(item, :content)
    summary = item_field(item, :summary)

    cond do
      not blank?(content) -> content
      not blank?(summary) -> summary
      true -> nil
    end
  end

  defp item_field(item, key) when is_map(item) do
    blank_to_nil(item[key] || item[Atom.to_string(key)])
  end

  defp maybe_promote_leading_image(markdown, image) when is_binary(image) and image != "" do
    case extract_opening_image(markdown) do
      {leading, rest} when is_binary(leading) ->
        if same_image?(leading, image), do: {image, rest}, else: {image, markdown}

      _ ->
        {image, markdown}
    end
  end

  defp maybe_promote_leading_image(markdown, _image) when is_binary(markdown) do
    extract_opening_image(markdown)
  end

  defp maybe_promote_leading_image(markdown, _image), do: {nil, markdown}

  # og:image and the first body <img> are often the same file at different
  # CDN sizes (Substack w_1200,c_fill vs w_1456,c_limit) or paths
  # (`/wp-content/uploads/…/scroogesquare.jpg` vs `/images/scroogesquare.jpg`).
  defp same_image?(left, right) do
    keys_left = image_keys(left)
    keys_right = image_keys(right)

    keys_left != MapSet.new() and not MapSet.disjoint?(keys_left, keys_right)
  end

  defp image_keys(url) do
    origin = ImageExtractor.normalize_url(url)

    [origin, image_basename(origin), image_basename(url), substack_media_id(origin), substack_media_id(url)]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> MapSet.new()
  end

  defp substack_media_id(url) when is_binary(url) do
    decoded =
      url
      |> ImageExtractor.normalize_url()
      |> URI.decode()

    case Regex.run(~r/([0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12})/i, decoded) do
      [_, id] -> String.downcase(id)
      _ -> nil
    end
  end

  defp substack_media_id(_), do: nil

  defp drop_opening_featured_html(html, image)
       when is_binary(html) and is_binary(image) and image != "" do
    case Floki.parse_fragment(html) do
      {:ok, nodes} -> nodes |> drop_opening_featured_nodes(image) |> Floki.raw_html()
      _ -> html
    end
  rescue
    _ -> html
  end

  defp drop_opening_featured_html(html, _), do: html

  defp drop_opening_featured_nodes([node], featured) do
    case node do
      {tag, attrs, children} ->
        [{tag, attrs, drop_opening_children(children, featured)}]

      _ ->
        [node]
    end
  end

  defp drop_opening_featured_nodes(nodes, featured) when is_list(nodes) do
    drop_opening_children(nodes, featured)
  end

  defp drop_opening_children(nodes, featured) do
    {kept, _} =
      Enum.reduce(nodes, {[], :opening}, fn
        node, {acc, :done} ->
          {acc ++ [node], :done}

        node, {acc, :opening} ->
          cond do
            blank_html_node?(node) ->
              {acc, :opening}

            short_credit_html?(node) ->
              {acc ++ [node], :opening}

            featured_image_block?(node, featured) ->
              {acc, :done}

            true ->
              {acc ++ [node], :done}
          end
      end)

    kept
  end

  defp blank_html_node?(text) when is_binary(text), do: String.trim(text) == ""
  defp blank_html_node?(_), do: false

  defp short_credit_html?({"p", _, _} = node) do
    text = node |> Floki.text() |> String.trim()

    image_urls_in(node) == [] and text != "" and
      length(String.split(text, ~r/\s+/, trim: true)) <= 10
  end

  defp short_credit_html?(_), do: false

  defp featured_image_block?(node, featured) do
    urls = image_urls_in(node)

    urls != [] and image_only_block?(node) and
      Enum.any?(urls, &same_image?(&1, featured))
  end

  defp image_only_block?({"img", _, _}), do: true
  defp image_only_block?({"figure", _, _}), do: true
  defp image_only_block?({"picture", _, _}), do: true
  defp image_only_block?({"a", _, children}), do: image_only_block_children?(children)

  defp image_only_block?({"p", _, children}) do
    image_only_block_children?(children) and
      String.trim(Floki.text({"p", [], children})) == ""
  end

  defp image_only_block?({"div", _, children}), do: image_only_block_children?(children)
  defp image_only_block?(_), do: false

  defp image_only_block_children?(children) do
    children
    |> Enum.reject(&blank_html_node?/1)
    |> Enum.all?(fn
      {"img", _, _} -> true
      {"figure", _, _} -> true
      {"picture", _, _} -> true
      {"a", _, inner} -> image_only_block_children?(inner)
      {"div", _, inner} -> image_only_block_children?(inner)
      {"p", _, inner} -> image_only_block_children?(inner) and String.trim(Floki.text({"p", [], inner})) == ""
      _ -> false
    end)
  end

  defp image_urls_in(nodes) when is_list(nodes), do: Enum.flat_map(nodes, &image_urls_in/1)

  defp image_urls_in({"img", attrs, children}) do
    img_urls(attrs) ++ image_urls_in(children)
  end

  defp image_urls_in({"source", attrs, children}) do
    img_urls(attrs) ++ image_urls_in(children)
  end

  defp image_urls_in({_, _, children}), do: image_urls_in(children)
  defp image_urls_in(_), do: []

  defp img_urls(attrs) do
    [
      html_attr_value(attrs, "src"),
      html_attr_value(attrs, "data-src"),
      srcset_head(html_attr_value(attrs, "srcset") || html_attr_value(attrs, "data-srcset")),
      data_attrs_src(html_attr_value(attrs, "data-attrs"))
    ]
    |> List.flatten()
    |> Enum.filter(&(is_binary(&1) and String.trim(&1) != ""))
  end

  defp srcset_head(srcset) when is_binary(srcset) and srcset != "" do
    case Regex.run(~r/(\S+)\s+\d+w/i, srcset) do
      [_, url] -> [url]
      _ -> []
    end
  end

  defp srcset_head(_), do: []

  defp data_attrs_src(json) when is_binary(json) and json != "" do
    case Jason.decode(json) do
      {:ok, %{"src" => src}} when is_binary(src) and src != "" -> [src]
      _ -> []
    end
  end

  defp data_attrs_src(_), do: []

  defp html_attr_value(attrs, name) do
    case List.keyfind(attrs, name, 0) do
      {_, value} -> value
      nil -> nil
    end
  end

  defp image_basename(url) do
    name =
      url
      |> URI.parse()
      |> Map.get(:path, "")
      |> Path.basename()
      |> String.downcase()
      |> String.replace(~r/-\d+x\d+(?=\.[a-z0-9]+$)/, "")
      |> String.replace(~r/-scaled(?=\.[a-z0-9]+$)/, "")

    if String.contains?(name, "."), do: name, else: ""
  end

  @linked_image ~r/\[!\[[^\]]*\]\(([^"\)]+)(?:\s+"[^"]*")?\s*\)\]\([^\)]+\)/
  @bare_image ~r/!\[[^\]]*\]\(\s*([^"\)]+)(?:\s+"[^"]*")?\s*\)/

  # First body image if it is still in the opening: at the top, after
  # player/watch links, a short credit line, or at the start of the
  # first prose paragraph. Substack often repeats the cover after
  # “By …” / “Von … auf Facebook.”
  defp extract_opening_image(markdown) when not is_binary(markdown), do: {nil, markdown}

  defp extract_opening_image(markdown) do
    case first_image_match(markdown) do
      {url, start, len} ->
        prefix = binary_part(markdown, 0, start)

        if opening_prefix?(prefix) do
          {url, remove_image_at(markdown, start, len)}
        else
          {nil, markdown}
        end

      nil ->
        {nil, markdown}
    end
  end

  defp first_image_match(markdown) do
    linked = image_match(markdown, @linked_image)
    bare = image_match(markdown, @bare_image)

    cond do
      linked && bare && elem(linked, 1) <= elem(bare, 1) -> linked
      linked -> linked
      bare -> bare
      true -> nil
    end
  end

  defp image_match(markdown, regex) do
    case Regex.run(regex, markdown, return: :index) do
      [{start, len} | captures] ->
        url =
          captures
          |> Enum.find_value(fn
            {pos, n} when n > 0 -> binary_part(markdown, pos, n)
            _ -> nil
          end)

        if is_binary(url), do: {url, start, len}

      _ ->
        nil
    end
  end

  defp opening_prefix?(prefix) do
    prefix
    |> String.split(~r/\n{2,}/)
    |> Enum.all?(&thin_opening_block?/1)
  end

  defp thin_opening_block?(block) do
    trimmed = String.trim(block)

    trimmed == "" or String.match?(trimmed, ~r/\A---+\z/) or lone_markdown_link?(trimmed) or
      short_credit?(trimmed)
  end

  # One short line (attribution, kicker) is still “opening”, unlike a
  # real first paragraph. Word count keeps “Von X auf Facebook.” thin
  # and “On this edition of Film, Literature …” substantial.
  defp short_credit?(text) do
    not String.contains?(text, "![") and
      not String.contains?(text, "\n") and
      length(String.split(text, ~r/\s+/, trim: true)) <= 10
  end

  defp lone_markdown_link?(text) do
    String.match?(text, ~r/\A\[[^\]]+\]\([^)]+\)\s*\z/)
  end

  defp remove_image_at(markdown, start, len) do
    {pre, rest} = String.split_at(markdown, start)
    {_gone, post} = String.split_at(rest, len)

    (pre <> post)
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> then(fn joined ->
      if String.trim(pre) == "", do: String.trim_leading(joined), else: joined
    end)
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
        attrs |> img_urls() |> List.first() |> blank_to_nil()
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

  defp parse_px(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_px(_), do: nil

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

  defp page_featured_image(html, opts) do
    url = opts.url

    cond do
      opts.fetch_page_image != true ->
        nil

      not is_binary(url) or url == "" ->
        nil

      full_html_document?(html) ->
        nil

      true ->
        case FeedFetcher.fetch_article(url) do
          {:ok, page} -> extract_meta(page).image
          _ -> nil
        end
    end
  end

  defp full_html_document?(html) when is_binary(html), do: String.match?(html, ~r/<html[\s>]/i)
  defp full_html_document?(_), do: false

  defp document_title(doc) do
    doc
    |> Floki.find("title")
    |> Floki.text()
    |> String.trim()
    |> blank_to_nil()
  end

  defp truncate_summary(nil), do: nil

  defp truncate_summary(text) when byte_size(text) > 500 do
    String.slice(text, 0, 497) <> "..."
  end

  defp truncate_summary(text), do: text

  defp blank?(value), do: blank_to_nil(value) == nil

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
