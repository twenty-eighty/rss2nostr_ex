defmodule Rss2Nostr.Processing.Composer do
  @moduledoc """
  Builds the Markdown that becomes a NIP-23 event from either feed XML
  or the article page, using per-source composition settings.
  """

  alias Rss2Nostr.Import.{FeedFetcher, FeedParser}
  alias Rss2Nostr.Nostr.Publisher
  alias Rss2Nostr.Processing.{BodySchema, Conversion, HtmlToMarkdown, Youtube}
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
    {"Generic post-content", ".post-content"}
  ]

  @type compose_opts :: %{
          optional(:fetch_source_from) => String.t(),
          optional(:body_selector) => String.t() | nil,
          optional(:start_at) => String.t() | nil,
          optional(:skip_classes) => [String.t()],
          optional(:conversion_rules) => [map()],
          optional(:title) => String.t() | nil,
          optional(:image) => String.t() | nil,
          optional(:summary) => String.t() | nil
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
      conversion_rules: []
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
        Conversion.parse_rules(options["conversion_rules"] || options[:conversion_rules])
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
        Conversion.parse_rules(params["conversion_rules"] || params[:conversion_rules])
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

    cond do
      mode == "fetch_from_url" or blank?(feed_html) ->
        case item_field(item, :link) do
          nil ->
            if blank?(feed_html) do
              {:error, "Article has no URL or feed content"}
            else
              {:ok, feed_html, "feed"}
            end

          url ->
            case FeedFetcher.fetch_article(url) do
              {:ok, html} -> {:ok, html, "url"}
              {:error, reason} -> {:error, reason}
            end
        end

      true ->
        {:ok, feed_html, "feed"}
    end
  end

  @doc """
  Extracts the article body with an optional CSS selector.
  Returns `{html, matched?}`.
  """
  @spec extract_body(String.t() | nil, String.t() | nil) :: {String.t() | nil, boolean()}
  def extract_body(html, _selector) when html in [nil, ""], do: {html, false}
  def extract_body(html, selector) when selector in [nil, ""], do: {html, false}

  def extract_body(html, selector) when is_binary(html) and is_binary(selector) do
    case Floki.parse_document(html) do
      {:ok, doc} ->
        case Floki.find(doc, selector) do
          [] -> {html, false}
          found -> {Floki.raw_html(found), true}
        end

      _ ->
        {html, false}
    end
  rescue
    _ -> {html, false}
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
          image: meta_content(doc, "meta[property='og:image']"),
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
    {body, matched} = extract_body(html, opts.body_selector)
    body = BodySchema.apply_start_at(body, opts.start_at)
    rules = opts.conversion_rules || []

    markdown =
      body
      |> HtmlToMarkdown.convert(
        skip_classes: opts.skip_classes,
        conversion_rules: rules
      )
      |> Youtube.enrich_markdown()

    meta = extract_meta(html)
    image = opts.image || meta.image
    {image, markdown} = maybe_promote_leading_image(markdown, image)

    %{
      markdown: markdown,
      html: render_html(markdown),
      selector_matched: matched,
      title: opts.title || meta.title,
      image: image,
      summary: opts.summary || meta.summary,
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
  Fetches a feed article and returns a Markdown preview of the Nostr event.
  """
  @spec preview(map()) :: {:ok, map()} | {:error, String.t()}
  def preview(params) when is_map(params) do
    url = params["url"] || params[:url]
    guid = params["guid"] || params[:guid]
    opts = opts_from_params(params)

    with {:ok, body} <- fetch_feed(url),
         type <- FeedParser.detect_feed_type(body) || params["type"] || params[:type],
         {:ok, items} <- parse_items(body, type),
         {:ok, item} <- find_item(items, guid) do
      case html_for_item(item, opts) do
        {:ok, html, html_source} ->
          article_url = item_field(item, :link) || url
          selector = preview_selector(opts, params, article_url)

          composed =
            compose(html, %{
              body_selector: selector,
              start_at: opts.start_at,
              skip_classes: opts.skip_classes,
              conversion_rules: opts.conversion_rules,
              title: item_field(item, :title),
              image: item_field(item, :image),
              summary: truncate_summary(item_field(item, :summary))
            })

          {extracted, _} = extract_body(html, selector)
          source = load_source(params)

          nostr =
            Publisher.preview_event(
              %{
                title: composed.title,
                content: composed.markdown,
                summary: composed.summary,
                image: composed.image,
                source_url: article_url,
                published_at: item_field(item, :published_at),
                language: source && source.language,
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
             nostr_inner: nil,
             nostr_inner_json: nil,
             nostr_encrypted: false,
             nostr_draft: nostr.draft,
             nostr_relays: nostr.relays
           }}

        {:error, reason} ->
          {:error, reason}
      end
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
      title: opts[:title] || opts["title"],
      image: opts[:image] || opts["image"],
      summary: opts[:summary] || opts["summary"]
    }
  end

  defp fetch_mode(%Source{fetch_source_from: mode}), do: fetch_mode(mode)

  defp fetch_mode(opts) when is_map(opts) do
    fetch_mode(opts[:fetch_source_from] || opts["fetch_source_from"])
  end

  defp fetch_mode("content"), do: "content"
  defp fetch_mode(_), do: "fetch_from_url"

  defp preview_selector(opts, params, article_url) do
    cond do
      is_binary(opts.body_selector) -> opts.body_selector
      auto_body_selector?(params) -> BodySchema.selector_for_url(article_url)
      true -> nil
    end
  end

  defp auto_body_selector?(params) do
    case params["body_selector_auto"] || params[:body_selector_auto] do
      value when value in [true, "true", "1", "on", "yes"] -> true
      value when value in [false, "false", "0", "off", "no"] -> false
      _ -> true
    end
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
    {image, markdown}
  end

  defp maybe_promote_leading_image(markdown, _image) when is_binary(markdown) do
    extract_leading_image(markdown)
  end

  defp maybe_promote_leading_image(markdown, _image), do: {nil, markdown}

  defp extract_leading_image(markdown) do
    linked = ~r/^\[!\[[^\]]*\]\(([^"\)]+)(?:\s+"[^"]*")?\s*\)\]\([^\)]+\)/
    bare = ~r/^!\[[^\]]*\]\(\s*([^"\)]+)(?:\s+"[^"]*")?\s*\)/

    cond do
      match = Regex.run(linked, markdown) ->
        [full, url] = match
        {url, strip_leading_image(markdown, full)}

      match = Regex.run(bare, markdown) ->
        [full, url] = match
        {url, strip_leading_image(markdown, full)}

      true ->
        {nil, markdown}
    end
  end

  defp strip_leading_image(markdown, matched) do
    markdown
    |> String.replace_prefix(matched, "")
    |> then(&Regex.replace(~r/\A---+\s*/, &1, ""))
    |> String.trim_leading()
  end

  defp meta_content(doc, selector) do
    doc
    |> Floki.find(selector)
    |> Floki.attribute("content")
    |> List.first()
    |> blank_to_nil()
  end

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
