defmodule Rss2Nostr.Processing.Composer.FeedPreview do
  @moduledoc false

  alias Rss2Nostr.Import.{FeedFetcher, FeedParser, ItemIdentity}
  alias Rss2Nostr.Nostr.{Event, Publisher}
  alias Rss2Nostr.Processing.{BodySchema, Composer, HtmlToMarkdown}
  alias Rss2Nostr.Processing.Composer.FeedItem
  alias Rss2Nostr.Sources
  alias Rss2Nostr.Sources.Source

  @spec preview(map()) :: {:ok, Composer.preview_result()} | {:error, String.t()}
  def preview(params) when is_map(params) do
    with {:ok, context} <- build_preview_context(params),
         {:ok, item} <- fetch_preview_item(context) do
      preview_item(item, context)
    end
  end

  @spec build_preview_context(map()) :: {:ok, Composer.preview_context()}
  defp build_preview_context(params) do
    source = params |> load_source() |> apply_excluded_hashtags(params)
    opts = Composer.opts_from_params(params)
    language = preview_language(params, source)

    {:ok,
     %{
       url: params["url"] || params[:url],
       guid: params["guid"] || params[:guid],
       source: source,
       opts: Map.put(opts, :language, language),
       params: params,
       rules: preview_conversion_rules(params, source, opts),
       language: language
     }}
  end

  @spec fetch_preview_item(Composer.preview_context()) :: {:ok, map()} | {:error, String.t()}
  defp fetch_preview_item(%{url: url, guid: guid, params: params}) do
    with {:ok, body} <- fetch_feed(url),
         type <- FeedParser.detect_feed_type(body) || params["type"] || params[:type],
         {:ok, items} <- parse_items(body, type),
         {:ok, item} <- find_item(items, guid) do
      {:ok, item}
    end
  end

  @spec preview_item(map(), Composer.preview_context()) ::
          {:ok, Composer.preview_result()} | {:error, String.t()}
  defp preview_item(item, context) do
    case Composer.html_for_item(item, context.opts) do
      {:ok, html, html_source} ->
        {:ok, build_preview_result(item, html, html_source, context)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec build_preview_result(map(), String.t(), String.t(), Composer.preview_context()) ::
          Composer.preview_result()
  defp build_preview_result(item, html, html_source, context) do
    %{url: feed_url, source: source, opts: opts, params: params, rules: rules, language: language} =
      context

    article_url =
      ItemIdentity.page_url(item) || FeedItem.field(item, :enclosure_url) ||
        FeedItem.field(item, :link) || feed_url

    selector = preview_selector(opts, params, article_url, html)

    composed =
      Composer.compose(html, %{
        body_selector: selector,
        body_selector_auto: auto_body_selector?(params),
        start_at: opts.start_at,
        skip_classes: opts.skip_classes,
        conversion_rules: rules,
        url: article_url,
        title: FeedItem.field(item, :title),
        image: FeedItem.field(item, :image),
        summary: truncate_summary(HtmlToMarkdown.plain_summary(FeedItem.field(item, :summary))),
        language: language,
        fetch_page_image: true
      })

    {extracted, _} = Composer.extract_body(html, selector)

    nostr =
      Publisher.preview_event(
        %{
          title: composed.title,
          content: composed.markdown,
          summary: composed.summary,
          image: composed.image,
          source_url: article_url,
          published_at: FeedItem.field(item, :published_at),
          language: language || (source && source.language),
          categories: FeedItem.field(item, :categories) || [],
          type: source && source.default_post_kind,
          pubkey: source && source.pubkey
        },
        source: source
      )

    %{
      title: composed.title,
      summary: composed.summary,
      image: composed.image,
      markdown: composed.markdown,
      html: composed.html,
      html_source: html_source,
      selector_matched: composed.selector_matched,
      guid: FeedItem.field(item, :guid),
      link: FeedItem.field(item, :link),
      link_groups: composed.link_groups,
      body_selector: selector || "",
      start_at: opts.start_at,
      body_regions: BodySchema.candidates(html, url: article_url, selected: selector || ""),
      start_blocks: BodySchema.start_blocks(extracted, selected: opts.start_at),
      nostr_event: nostr.event,
      nostr_event_json: nostr.json,
      hashtags: event_hashtags(nostr.event),
      nostr_parts: nostr.parts,
      nostr_parts_json:
        Enum.map(nostr.parts, fn event ->
          Jason.encode!(["EVENT", event], pretty: true)
        end),
      nostr_parts_preview: Composer.preview_parts(nostr.parts),
      nostr_inner: nil,
      nostr_inner_json: nil,
      nostr_encrypted: false,
      nostr_draft: nostr.draft,
      nostr_plain_draft: nostr.plain_draft,
      nostr_relays: nostr.relays
    }
  end

  @spec preview_conversion_rules(map(), Source.t(), Composer.compose_opts()) :: [map()]
  defp preview_conversion_rules(params, source, opts) do
    if Map.has_key?(params, "conversion_rules") or Map.has_key?(params, :conversion_rules) do
      opts.conversion_rules
    else
      source
      |> Composer.opts_from_source()
      |> Map.get(:conversion_rules, [])
    end
  end

  @spec event_hashtags(map()) :: [String.t()]
  defp event_hashtags(%{tags: tags}) when is_list(tags) do
    for ["t", tag] <- tags, do: tag
  end

  defp event_hashtags(_), do: []

  @spec apply_excluded_hashtags(Source.t(), map()) :: Source.t()
  defp apply_excluded_hashtags(source, params) do
    if Map.has_key?(params, "excluded_hashtags") or Map.has_key?(params, :excluded_hashtags) do
      tags =
        Event.normalize_hashtags(params["excluded_hashtags"] || params[:excluded_hashtags])

      case source do
        %Source{} = source -> %{source | excluded_hashtags: tags}
        nil -> %Source{excluded_hashtags: tags}
      end
    else
      source
    end
  end

  @spec load_source(map()) :: Source.t()
  defp load_source(params) do
    case load_existing_source(params) do
      %Source{} = source -> source
      _ -> build_preview_source(params)
    end
  end

  @spec load_existing_source(map()) :: Source.t() | nil
  defp load_existing_source(params) do
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

  @spec build_preview_source(map()) :: Source.t()
  defp build_preview_source(params) do
    publish_as = blank_to_nil(params["publish_as"] || params[:publish_as]) || "draft"

    %Source{
      url: blank_to_nil(params["url"] || params[:url]) || "",
      language: blank_to_nil(params["language"] || params[:language]) || "de",
      publish_as: publish_as,
      default_post_kind: preview_post_kind(publish_as),
      pubkey: blank_to_nil(params["pubkey"] || params[:pubkey]),
      fetch_source_from:
        blank_to_nil(params["fetch_source_from"] || params[:fetch_source_from]) ||
          "fetch_from_url",
      fixed_hashtags:
        Event.normalize_hashtags(params["fixed_hashtags"] || params[:fixed_hashtags] || []),
      options: preview_options(params)
    }
  end

  @spec preview_post_kind(String.t()) :: 30_023 | 30_024 | 34_235
  defp preview_post_kind("article"), do: 30_023
  defp preview_post_kind("video"), do: 34_235
  defp preview_post_kind(_), do: 30_024

  @spec preview_options(map()) :: map()
  defp preview_options(params) do
    %{}
    |> maybe_preview_option("mirror_media", params)
    |> maybe_preview_option("body_selector", params)
    |> maybe_preview_option("start_at", params)
    |> maybe_preview_skip_classes(params)
    |> maybe_preview_conversion_rules(params)
  end

  @spec maybe_preview_option(map(), String.t(), map()) :: map()
  defp maybe_preview_option(options, key, params) do
    case blank_to_nil(params[key] || params[String.to_atom(key)]) do
      nil -> options
      value -> Map.put(options, key, value)
    end
  end

  @spec maybe_preview_skip_classes(map(), map()) :: map()
  defp maybe_preview_skip_classes(options, params) do
    if Map.has_key?(params, "skip_classes") or Map.has_key?(params, :skip_classes) do
      Map.put(
        options,
        "skip_classes",
        Composer.parse_skip_classes(params["skip_classes"] || params[:skip_classes])
      )
    else
      options
    end
  end

  @spec maybe_preview_conversion_rules(map(), map()) :: map()
  defp maybe_preview_conversion_rules(options, params) do
    if Map.has_key?(params, "conversion_rules") or Map.has_key?(params, :conversion_rules) do
      Map.put(
        options,
        "conversion_rules",
        Rss2Nostr.Processing.Conversion.parse_rules(
          params["conversion_rules"] || params[:conversion_rules]
        )
      )
    else
      options
    end
  end

  @spec fetch_feed(String.t() | nil) :: {:ok, String.t()} | {:error, String.t()}
  defp fetch_feed(url) when is_binary(url) and url != "" do
    FeedFetcher.fetch(url)
  end

  defp fetch_feed(_), do: {:error, "Feed URL is required"}

  @spec parse_items(String.t(), atom() | nil) :: {:ok, [map()]} | {:error, String.t()}
  defp parse_items(_body, nil), do: {:error, "Not an RSS or Atom feed"}

  defp parse_items(body, type) do
    case FeedParser.parse(body, type) do
      {:ok, []} -> {:error, "Feed has no articles"}
      {:ok, items} -> {:ok, items}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec find_item([map()], String.t() | nil) :: {:ok, map()} | {:error, String.t()}
  defp find_item([first | _], guid) when guid in [nil, ""], do: {:ok, first}

  defp find_item(items, guid) do
    case Enum.find(items, fn item ->
           FeedItem.field(item, :guid) == guid or FeedItem.field(item, :link) == guid
         end) do
      nil -> {:error, "Article not found in feed"}
      item -> {:ok, item}
    end
  end

  @spec preview_language(map(), Source.t()) :: String.t() | nil
  defp preview_language(params, source) do
    blank_to_nil(params["language"] || params[:language]) ||
      (source && blank_to_nil(source.language))
  end

  @spec preview_selector(Composer.compose_opts(), map(), String.t() | nil, String.t() | nil) :: String.t() | nil
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

  @spec auto_body_selector?(map()) :: boolean()
  defp auto_body_selector?(params) do
    case params["body_selector_auto"] || params[:body_selector_auto] do
      value when value in [true, "true", "1", "on", "yes"] -> true
      value when value in [false, "false", "0", "off", "no"] -> false
      _ -> true
    end
  end

  @spec truncate_summary(String.t() | nil) :: String.t() | nil
  defp truncate_summary(nil), do: nil

  defp truncate_summary(text) when byte_size(text) > 500 do
    String.slice(text, 0, 497) <> "..."
  end

  defp truncate_summary(text), do: text

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
