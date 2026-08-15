defmodule Rss2Nostr.Web.API.Sources do
  @moduledoc """
  API handlers for source operations.
  """

  alias Rss2Nostr.Sources
  alias Rss2Nostr.Sources.Source
  alias Rss2Nostr.Import.{FeedDiscovery, Importer}
  alias Rss2Nostr.Processing.{Composer, Conversion, Processor}
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

    case FeedDiscovery.preview(url) do
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

  @spec create(map()) :: {:ok, Source.t()} | {:error, Ecto.Changeset.t()}
  def create(params) do
    attrs =
      %{
        name: params["name"],
        url: params["url"],
        type: params["type"] || "atom",
        language: params["language"] || "de",
        active: true,
        mode: "setup",
        public: truthy?(params["public"]),
        pubkey: blank_to_nil(params["pubkey"]),
        signing_nsec: blank_to_nil(params["signing_nsec"]),
        bunker_connection: blank_to_nil(params["bunker_connection"]),
        publish_after_date: parse_datetime(params["start_published_at"]),
        fetch_source_from: params["fetch_source_from"] || "fetch_from_url",
        options: composition_options(params)
      }
      |> maybe_put(:publish_as, blank_to_nil(params["publish_as"]))

    Sources.create_source(attrs)
  end

  @spec update(Source.t() | String.t(), map()) ::
          {:ok, Source.t()} | {:error, atom() | Ecto.Changeset.t()}
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
      |> maybe_put_bunker(params)
      |> maybe_put(:signing_nsec, blank_to_nil(params["signing_nsec"]))
      |> maybe_put(:publish_after_date, parse_datetime(params["start_published_at"]))
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
      |> Enum.filter(&(&1.source_id == source.id))

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
      |> Enum.map(&Processor.process_post/1)

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

  @spec toggle(String.t()) :: {:ok, Source.t()} | {:error, atom() | Ecto.Changeset.t()}
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

  defp source_to_map(source) do
    %{
      id: source.id,
      name: source.name,
      url: source.url,
      type: source.type,
      active: source.active,
      mode: source.mode,
      publish_as: source.publish_as,
      language: source.language,
      public: source.public,
      pubkey: source.pubkey,
      default_post_kind: source.default_post_kind
    }
  end

  defp composition_options(params, existing \\ %{}) do
    existing = existing || %{}

    existing
    |> maybe_put("start_guid", blank_to_nil(params["start_guid"]))
    |> maybe_merge_compose(params)
  end

  defp maybe_merge_compose(options, params) do
    if Map.has_key?(params, "body_selector") or Map.has_key?(params, "skip_classes") or
         Map.has_key?(params, "conversion_rules") or Map.has_key?(params, "start_at") do
      options
      |> Map.put("body_selector", blank_to_nil(params["body_selector"]))
      |> Map.put("start_at", blank_to_nil(params["start_at"]))
      |> Map.put("skip_classes", Composer.parse_skip_classes(params["skip_classes"]))
      |> Map.put("conversion_rules", Conversion.parse_rules(params["conversion_rules"]))
    else
      options
    end
  end

  defp selected_ids(params) do
    List.wrap(params["post_ids"] || params["post_ids[]"] || [])
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_bunker(attrs, params) do
    if Map.has_key?(params, "bunker_connection") do
      Map.put(attrs, :bunker_connection, blank_to_nil(params["bunker_connection"]))
    else
      attrs
    end
  end

  defp maybe_put_public(attrs, params, source) do
    if Map.has_key?(params, "public") do
      Map.put(attrs, :public, truthy?(params["public"]))
    else
      Map.put(attrs, :public, source.public)
    end
  end

  defp truthy?(value) when value in [true, "true", "1", "on", "yes"], do: true
  defp truthy?(list) when is_list(list), do: Enum.any?(list, &truthy?/1)
  defp truthy?(_), do: false

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(_), do: nil

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

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int_id, ""} when int_id > 0 -> {:ok, int_id}
      _ -> {:error, :invalid_id}
    end
  end

  defp parse_id(_), do: {:error, :invalid_id}
end
