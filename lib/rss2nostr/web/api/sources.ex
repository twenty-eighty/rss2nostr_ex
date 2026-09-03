defmodule Rss2Nostr.Web.API.Sources do
  @moduledoc """
  API handlers for source operations.
  """

  alias Rss2Nostr.Sources
  alias Rss2Nostr.Sources.Source
  alias Rss2Nostr.Import.{FeedDiscovery, Importer}
  alias Rss2Nostr.Processing.{BodySchema, Composer, Conversion, Processor}
  alias Rss2Nostr.Posts
  alias Rss2Nostr.Posts.Post
  alias Rss2Nostr.Web.API.Posts, as: PostsAPI

  @spec list() :: [map()]
  def list do
    Sources.list_sources()
    |> Enum.map(&source_to_map/1)
  end

  @spec discover(map()) :: {:ok, map()} | {:error, String.t()}
  def discover(params) do
    url = params["url"] || params[:url]

    case FeedDiscovery.discover(url) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec preview(map()) :: {:ok, map()} | {:error, String.t()}
  def preview(params) do
    url = params["url"] || params[:url]
    force? = truthy?(params["force"] || params[:force])

    case FeedDiscovery.preview(url, force: force?) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec get(String.t()) :: {:ok, Source.t()} | {:error, atom()}
  def get(id) do
    with {:ok, source_id} <- parse_id(id),
         %Source{} = source <- Sources.get_source(source_id) do
      {:ok, source}
    else
      nil -> {:error, :not_found}
      {:error, :invalid_id} -> {:error, :invalid_id}
    end
  end

  @spec compose_preview(map()) :: {:ok, map()} | {:error, String.t()}
  def compose_preview(params) do
    Composer.preview(params)
  end

  @type source_options :: %{String.t() => term()}

  @spec create(map()) :: {:ok, Source.t()} | {:error, Ecto.Changeset.t()}
  def create(params) do
    attrs =
      %{
        name: params["name"],
        url: params["url"],
        type: params["type"] || "atom",
        language: params["language"] || "de",
        active: active?(params),
        mode: blank_to_nil(params["mode"]) || "setup",
        public: truthy?(params["public"]),
        pubkey: blank_to_nil(params["pubkey"]),
        signing_nsec: blank_to_nil(params["signing_nsec"]),
        bunker_connection: blank_to_nil(params["bunker_connection"]),
        publish_after_date: parse_datetime(params["start_published_at"]),
        fetch_source_from: params["fetch_source_from"] || "fetch_from_url",
        staging_hold_minutes: parse_hold_minutes(params["staging_hold_minutes"]) || 0,
        notify_pubkey: blank_to_nil(params["notify_pubkey"]),
        options: composition_options(params)
      }
      |> maybe_put(:publish_as, blank_to_nil(params["publish_as"]))
      |> maybe_put_fixed_hashtags(params)
      |> maybe_put_excluded_hashtags(params)

    Sources.create_source(attrs)
  end

  @spec update(Source.t() | String.t(), map()) ::
          {:ok, Source.t()} | {:error, :not_found | :invalid_id | Ecto.Changeset.t()}
  def update(%Source{} = source, params) do
    options = composition_options(params, source.options || %{})

    attrs =
      %{options: options}
      |> maybe_put(:name, blank_to_nil(params["name"]))
      |> maybe_put(:url, blank_to_nil(params["url"]))
      |> maybe_put(:language, blank_to_nil(params["language"]))
      |> maybe_put(:pubkey, params["pubkey"])
      |> maybe_put(:fetch_source_from, blank_to_nil(params["fetch_source_from"]))
      |> maybe_put(:publish_as, blank_to_nil(params["publish_as"]))
      |> maybe_put(:mode, blank_to_nil(params["mode"]))
      |> maybe_put_active(params)
      |> maybe_put_bunker(params)
      |> maybe_put(:signing_nsec, blank_to_nil(params["signing_nsec"]))
      |> put_publish_after_date(params)
      |> maybe_put_hold_minutes(params)
      |> maybe_put_notify_pubkey(params)
      |> maybe_put_fixed_hashtags(params)
      |> maybe_put_excluded_hashtags(params)
      |> maybe_put_public(params, source)

    Sources.update_source(source, attrs)
  end

  def update(id, params) when is_binary(id) do
    case get(id) do
      {:ok, source} -> update(source, params)
      error -> error
    end
  end

  @spec import_now(Source.t() | String.t()) ::
          {:ok, map()} | {:error, atom()}
  def import_now(%Source{} = source) do
    result = Importer.import_from_source(source)

    processed =
      source.id
      |> Posts.list_posts_for_source(limit: 200)
      |> Enum.filter(&(&1.status == Post.status_new()))
      |> Enum.map(&Processor.process_post/1)
      |> Enum.count(&match?({:ok, _}, &1))

    {:ok, Map.put(result, :processed, processed)}
  end

  def import_now(id) when is_binary(id) do
    case get(id) do
      {:ok, source} -> import_now(source)
      error -> error
    end
  end

  @spec publish_selected(Source.t() | String.t(), map()) ::
          {:ok, map()} | {:error, atom() | String.t()}
  def publish_selected(%Source{} = source, params) do
    ids = selected_ids(params)

    posts =
      ids
      |> Posts.get_posts(preload: [:source])
      |> Enum.filter(&(&1.source_id == source.id and &1.status == Post.status_processed()))

    PostsAPI.publish_posts(posts)
  end

  def publish_selected(id, params) when is_binary(id) do
    case get(id) do
      {:ok, source} -> publish_selected(source, params)
      error -> error
    end
  end

  @spec reprocess_selected(Source.t() | String.t(), map()) ::
          {:ok, map()} | {:error, atom()}
  def reprocess_selected(%Source{} = source, params) do
    ids = selected_ids(params)

    results =
      ids
      |> Posts.get_posts()
      |> Enum.filter(&(&1.source_id == source.id))
      |> Enum.map(&Processor.reprocess_post/1)

    {:ok,
     %{
       processed: Enum.count(results, &match?({:ok, _}, &1)),
       errors: Enum.count(results, &match?({:error, _}, &1))
     }}
  end

  def reprocess_selected(id, params) when is_binary(id) do
    case get(id) do
      {:ok, source} -> reprocess_selected(source, params)
      error -> error
    end
  end

  @spec toggle(String.t()) ::
          {:ok, Source.t()} | {:error, :not_found | :invalid_id | Ecto.Changeset.t()}
  def toggle(id) do
    with {:ok, source_id} <- parse_id(id),
         %Source{} = source <- Sources.get_source(source_id) do
      if source.active do
        Sources.disable_source(source)
      else
        Sources.enable_source(source)
      end
    else
      nil -> {:error, :not_found}
      {:error, :invalid_id} -> {:error, :invalid_id}
    end
  end

  @spec duplicate(Source.t() | String.t(), map()) ::
          {:ok, Source.t()} | {:error, atom() | Ecto.Changeset.t()}
  def duplicate(source, attrs \\ %{})

  def duplicate(%Source{} = source, attrs) do
    Sources.duplicate_source(source, attrs)
  end

  def duplicate(id, attrs) when is_binary(id) do
    case get(id) do
      {:ok, source} -> duplicate(source, attrs)
      error -> error
    end
  end

  @spec delete(String.t()) :: {:ok, Source.t()} | {:error, atom()}
  def delete(id) do
    with {:ok, source_id} <- parse_id(id),
         %Source{} = source <- Sources.get_source(source_id) do
      Sources.delete_source(source)
    else
      nil -> {:error, :not_found}
      {:error, :invalid_id} -> {:error, :invalid_id}
    end
  end

  @spec source_to_map(Source.t()) :: map()
  defp source_to_map(source) do
    %{
      id: source.id,
      name: source.name,
      url: source.url,
      type: source.type,
      active: source.active,
      mode: source.mode,
      publish_as: source.publish_as,
      mirror_media:
        if(Rss2Nostr.Sources.Source.mirror_media?(source), do: "blossom", else: "original"),
      language: source.language,
      public: source.public,
      pubkey: source.pubkey,
      default_post_kind: source.default_post_kind
    }
  end

  @spec composition_options(map(), source_options()) :: source_options()
  defp composition_options(params, existing \\ %{}) do
    existing = existing || %{}

    existing
    |> put_start_guid(params)
    |> maybe_put_mirror_media(params)
    |> maybe_merge_compose(params)
    |> maybe_infer_body_selector(params)
  end

  @future_only_guid "__future_only__"

  @spec put_start_guid(source_options(), map()) :: source_options()
  defp put_start_guid(options, params) do
    if Map.has_key?(params, "start_guid") do
      case normalize_start_guid(params["start_guid"]) do
        nil -> Map.delete(options, "start_guid")
        guid -> Map.put(options, "start_guid", guid)
      end
    else
      options
    end
  end

  @spec normalize_start_guid(term()) :: String.t() | nil
  defp normalize_start_guid(@future_only_guid), do: nil
  defp normalize_start_guid(value), do: blank_to_nil(value)

  @spec put_publish_after_date(map(), map()) :: map()
  defp put_publish_after_date(attrs, params) do
    if Map.has_key?(params, "start_published_at") do
      Map.put(attrs, :publish_after_date, parse_datetime(params["start_published_at"]))
    else
      attrs
    end
  end

  @spec maybe_put_mirror_media(map(), map()) :: map()
  defp maybe_put_mirror_media(options, params) do
    if Map.has_key?(params, "mirror_media") do
      Map.put(options, "mirror_media", normalize_mirror_media(params["mirror_media"]))
    else
      options
    end
  end

  @spec normalize_mirror_media(term()) :: String.t()
  defp normalize_mirror_media(value) when value in ["original", "false", false, "0"],
    do: "original"

  defp normalize_mirror_media(_), do: "blossom"

  @spec maybe_infer_body_selector(map(), map()) :: map()
  defp maybe_infer_body_selector(options, params) do
    explicit_blank? =
      Map.has_key?(params, "body_selector") and
        is_nil(blank_to_nil(params["body_selector"]))

    cond do
      present_selector?(options["body_selector"]) ->
        options

      explicit_blank? ->
        options

      inferred = BodySchema.selector_for_url(params["url"]) ->
        Map.put(options, "body_selector", inferred)

      true ->
        options
    end
  end

  @spec present_selector?(term()) :: boolean()
  defp present_selector?(value) when is_binary(value), do: String.trim(value) != ""
  defp present_selector?(_), do: false

  @spec maybe_merge_compose(map(), map()) :: map()
  defp maybe_merge_compose(options, params) do
    if Map.has_key?(params, "body_selector") or Map.has_key?(params, "skip_classes") or
         Map.has_key?(params, "conversion_rules") or Map.has_key?(params, "start_at") do
      options
      |> Map.put("body_selector", blank_to_nil(params["body_selector"]))
      |> Map.put("start_at", blank_to_nil(params["start_at"]))
      |> Map.put("skip_classes", Composer.parse_skip_classes(params["skip_classes"]))
      |> maybe_put_conversion_rules(params)
    else
      options
    end
  end

  @spec selected_ids(map()) :: [term()]
  defp selected_ids(params) do
    List.wrap(params["post_ids"] || params["post_ids[]"] || [])
  end

  @spec maybe_put_conversion_rules(map(), map()) :: map()
  defp maybe_put_conversion_rules(options, params) do
    if Map.has_key?(params, "conversion_rules") do
      Map.put(options, "conversion_rules", Conversion.parse_rules(params["conversion_rules"]))
    else
      options
    end
  end

  @spec maybe_put(map(), atom() | String.t(), term()) :: map()
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  @spec maybe_put_bunker(map(), map()) :: map()
  defp maybe_put_bunker(attrs, params) do
    if Map.has_key?(params, "bunker_connection") do
      Map.put(attrs, :bunker_connection, blank_to_nil(params["bunker_connection"]))
    else
      attrs
    end
  end

  @spec maybe_put_hold_minutes(map(), map()) :: map()
  defp maybe_put_hold_minutes(attrs, params) do
    if Map.has_key?(params, "staging_hold_minutes") do
      Map.put(
        attrs,
        :staging_hold_minutes,
        parse_hold_minutes(params["staging_hold_minutes"]) || 0
      )
    else
      attrs
    end
  end

  @spec maybe_put_notify_pubkey(map(), map()) :: map()
  defp maybe_put_notify_pubkey(attrs, params) do
    if Map.has_key?(params, "notify_pubkey") do
      Map.put(attrs, :notify_pubkey, params["notify_pubkey"] || "")
    else
      attrs
    end
  end

  @spec maybe_put_fixed_hashtags(map(), map()) :: map()
  defp maybe_put_fixed_hashtags(attrs, params) do
    if Map.has_key?(params, "fixed_hashtags") do
      Map.put(attrs, :fixed_hashtags, params["fixed_hashtags"])
    else
      attrs
    end
  end

  @spec maybe_put_excluded_hashtags(map(), map()) :: map()
  defp maybe_put_excluded_hashtags(attrs, params) do
    if Map.has_key?(params, "excluded_hashtags") do
      Map.put(attrs, :excluded_hashtags, params["excluded_hashtags"])
    else
      attrs
    end
  end

  @spec parse_hold_minutes(term()) :: non_neg_integer() | nil
  defp parse_hold_minutes(nil), do: nil
  defp parse_hold_minutes(""), do: 0
  defp parse_hold_minutes(value) when is_integer(value) and value >= 0, do: value

  defp parse_hold_minutes(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} when int >= 0 -> int
      _ -> nil
    end
  end

  defp parse_hold_minutes(_), do: nil

  @spec maybe_put_public(map(), map(), Source.t()) :: map()
  defp maybe_put_public(attrs, params, source) do
    if Map.has_key?(params, "public") do
      Map.put(attrs, :public, truthy?(params["public"]))
    else
      Map.put(attrs, :public, source.public)
    end
  end

  @spec maybe_put_active(map(), map(), Source.t() | nil) :: map()
  defp maybe_put_active(attrs, params, _source \\ nil) do
    if Map.has_key?(params, "active") do
      Map.put(attrs, :active, truthy?(params["active"]))
    else
      attrs
    end
  end

  @spec active?(map()) :: boolean()
  defp active?(params) do
    if Map.has_key?(params, "active"), do: truthy?(params["active"]), else: true
  end

  @spec truthy?(term()) :: boolean()
  defp truthy?(value) when value in [true, "true", "1", "on", "yes"], do: true
  defp truthy?(list) when is_list(list), do: Enum.any?(list, &truthy?/1)
  defp truthy?(_), do: false

  @spec blank_to_nil(term()) :: term()
  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(_), do: nil

  @spec parse_datetime(term()) :: DateTime.t() | nil
  defp parse_datetime(nil), do: nil
  defp parse_datetime(""), do: nil

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _} -> DateTime.truncate(datetime, :second)
      _ -> nil
    end
  end

  defp parse_datetime(%DateTime{} = datetime), do: DateTime.truncate(datetime, :second)
  defp parse_datetime(_), do: nil

  @spec parse_id(term()) :: {:ok, pos_integer()} | {:error, :invalid_id}
  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int_id, ""} when int_id > 0 -> {:ok, int_id}
      _ -> {:error, :invalid_id}
    end
  end

  defp parse_id(_), do: {:error, :invalid_id}
end
