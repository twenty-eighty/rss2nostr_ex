defmodule Rss2Nostr.MCP.Actions do
  @moduledoc false

  alias Rss2Nostr.Processing.{Composer, Processor}
  alias Rss2Nostr.Nostr.{FollowList, Signer}
  alias Rss2Nostr.Posts
  alias Rss2Nostr.Posts.Post
  alias Rss2Nostr.Sources.Source
  alias Rss2Nostr.Web.API.{Posts, Scheduler, Settings, Sources, Status}

  @type args :: map()
  @type action_result :: {:ok, term()} | {:error, String.t()}
  @type status_result :: {:ok, Status.overview()} | {:error, String.t()}

  @max_bulk_reprocess 500

  @spec get_status() :: status_result()
  def get_status, do: {:ok, Status.overview()}

  @spec get_settings() :: action_result()
  def get_settings, do: {:ok, Settings.get()}

  @spec list_sources() :: action_result()
  def list_sources do
    structs = Rss2Nostr.Sources.list_sources()
    summaries = Sources.list()

    sources =
      Enum.zip(summaries, structs)
      |> Enum.map(fn {summary, source} ->
        summary
        |> Map.put(:author_pubkey, Signer.author_pubkey(source))
        |> Map.put(:follow_list, FollowList.source_membership_map(source))
      end)

    {:ok, %{sources: sources}}
  end

  @spec get_source(args()) :: action_result()
  def get_source(args) do
    with {:ok, id} <- require_id(args, :source_id) do
      case Sources.get(id) do
        {:ok, source} -> {:ok, source_detail(source)}
        {:error, :not_found} -> {:error, "Source not found"}
        {:error, :invalid_id} -> {:error, "Invalid source_id"}
      end
    end
  end

  @spec discover_feeds(args()) :: action_result()
  def discover_feeds(args) do
    with {:ok, url} <- require_string(args, :url) do
      Sources.discover(%{"url" => url})
    end
  end

  @spec preview_feed(args()) :: action_result()
  def preview_feed(args) do
    with {:ok, url} <- require_string(args, :url) do
      Sources.preview(%{"url" => url})
    end
  end

  @spec preview_compose(args()) :: action_result()
  def preview_compose(args) do
    params =
      string_params(
        args,
        ~w(
          url guid type fetch_source_from body_selector start_at skip_classes excluded_hashtags
          language publish_as pubkey fixed_hashtags mirror_media conversion_rules body_selector_auto
        )a
      )

    params =
      case arg(args, :source_id) do
        nil -> params
        id -> Map.put(params, "source_id", to_string(id))
      end

    Sources.compose_preview(params)
  end

  @spec add_source(args()) :: action_result()
  def add_source(args) do
    with {:ok, name} <- require_string(args, :name),
         {:ok, url} <- require_string(args, :url) do
      params =
        string_params(args, [
          :type,
          :language,
          :publish_as,
          :mirror_media,
          :mode,
          :active,
          :public,
          :pubkey,
          :signing_nsec,
          :bunker_connection,
          :fetch_source_from,
          :body_selector,
          :start_at,
          :skip_classes,
          :start_guid,
          :start_published_at,
          :staging_hold_minutes,
          :notify_pubkey,
          :fixed_hashtags,
          :excluded_hashtags,
          :conversion_rules
        ])
        |> Map.merge(%{"name" => name, "url" => url})

      case Sources.create(params) do
        {:ok, source} -> {:ok, source_detail(source)}
        {:error, changeset} -> {:error, format_changeset(changeset)}
      end
    end
  end

  @spec update_source(args()) :: action_result()
  def update_source(args) do
    with {:ok, id} <- require_id(args, :source_id) do
      params =
        string_params(args, [
          :name,
          :url,
          :language,
          :publish_as,
          :mirror_media,
          :mode,
          :active,
          :public,
          :pubkey,
          :signing_nsec,
          :bunker_connection,
          :fetch_source_from,
          :body_selector,
          :start_at,
          :skip_classes,
          :start_guid,
          :start_published_at,
          :staging_hold_minutes,
          :notify_pubkey,
          :fixed_hashtags,
          :excluded_hashtags,
          :conversion_rules
        ])

      case Sources.update(id, params) do
        {:ok, source} -> {:ok, source_detail(source)}
        {:error, :not_found} -> {:error, "Source not found"}
        {:error, :invalid_id} -> {:error, "Invalid source_id"}
        {:error, %Ecto.Changeset{} = changeset} -> {:error, format_changeset(changeset)}
      end
    end
  end

  @spec toggle_source(args()) :: action_result()
  def toggle_source(args) do
    with {:ok, id} <- require_id(args, :source_id) do
      case Sources.toggle(id) do
        {:ok, source} -> {:ok, source_detail(source)}
        {:error, :not_found} -> {:error, "Source not found"}
        {:error, :invalid_id} -> {:error, "Invalid source_id"}
        {:error, %Ecto.Changeset{} = changeset} -> {:error, format_changeset(changeset)}
      end
    end
  end

  @spec duplicate_source(args()) :: action_result()
  def duplicate_source(args) do
    with {:ok, id} <- require_id(args, :source_id) do
      attrs =
        case arg(args, :name) do
          name when is_binary(name) and name != "" -> %{name: name}
          _ -> %{}
        end

      case Sources.duplicate(id, attrs) do
        {:ok, source} -> {:ok, source_detail(source)}
        {:error, :not_found} -> {:error, "Source not found"}
        {:error, changeset} -> {:error, format_changeset(changeset)}
      end
    end
  end

  @spec delete_source(args()) :: action_result()
  def delete_source(args) do
    with {:ok, id} <- require_id(args, :source_id) do
      case Sources.delete(id) do
        {:ok, source} -> {:ok, %{deleted: true, id: source.id, name: source.name}}
        {:error, :not_found} -> {:error, "Source not found"}
        {:error, :invalid_id} -> {:error, "Invalid source_id"}
      end
    end
  end

  @spec import_source(args()) :: action_result()
  def import_source(args) do
    with {:ok, id} <- require_id(args, :source_id) do
      case Sources.import_now(id) do
        {:ok, result} -> {:ok, result}
        {:error, :not_found} -> {:error, "Source not found"}
        {:error, reason} -> {:error, inspect(reason)}
      end
    end
  end

  @spec reprocess_posts(args()) :: action_result()
  def reprocess_posts(args) do
    with {:ok, source_id} <- require_id(args, :source_id),
         {:ok, post_ids} <- require_id_list(args, :post_ids) do
      case Sources.reprocess_selected(source_id, %{"post_ids" => post_ids}) do
        {:ok, result} -> {:ok, result}
        {:error, :not_found} -> {:error, "Source not found"}
        {:error, reason} -> {:error, inspect(reason)}
      end
    end
  end

  @spec reprocess_errors(args()) :: action_result()
  def reprocess_errors(args) do
    source_id = optional_int(args, :source_id, nil)

    opts =
      [status: Post.status_error(), limit: @max_bulk_reprocess]
      |> maybe_kw(:source_id, source_id)

    posts = Rss2Nostr.Posts.list_posts(opts)

    results = Enum.map(posts, &Processor.reprocess_post/1)

    {:ok,
     %{
       processed: Enum.count(results, &match?({:ok, _}, &1)),
       errors: Enum.count(results, &match?({:error, _}, &1)),
       post_ids: Enum.map(posts, & &1.id)
     }}
  end

  @spec publish_source_posts(args()) :: action_result()
  def publish_source_posts(args) do
    with {:ok, source_id} <- require_id(args, :source_id),
         {:ok, post_ids} <- require_id_list(args, :post_ids) do
      case Sources.publish_selected(source_id, %{"post_ids" => post_ids}) do
        {:ok, result} -> {:ok, result}
        {:error, :not_found} -> {:error, "Source not found"}
        {:error, reason} -> {:error, format_error(reason)}
      end
    end
  end

  @spec list_posts(args()) :: action_result()
  def list_posts(args) do
    page = optional_int(args, :page, 1)
    per_page = min(optional_int(args, :per_page, 20), 100)
    status = optional_string(args, :status)
    q = optional_string(args, :q)
    source_id = optional_int(args, :source_id, nil)

    opts =
      [limit: per_page, offset: (page - 1) * per_page]
      |> maybe_kw(:status, status && status_value(status))
      |> maybe_kw(:source_id, source_id)
      |> maybe_kw(:q, q)

    posts = Rss2Nostr.Posts.list_posts(opts)

    {:ok,
     %{
       posts: Enum.map(posts, &post_summary/1),
       page: page,
       per_page: per_page
     }}
  end

  @spec get_post(args()) :: action_result()
  def get_post(args) do
    with {:ok, id} <- require_id(args, :post_id) do
      case Integer.parse(id) do
        {post_id, ""} ->
          case Rss2Nostr.Posts.get_post(post_id, preload: [:source]) do
            nil -> {:error, "Post not found"}
            post -> {:ok, post_detail(post)}
          end

        _ ->
          {:error, "Invalid post_id"}
      end
    end
  end

  @spec process_post(args()) :: action_result()
  def process_post(args) do
    with {:ok, id} <- require_id(args, :post_id) do
      case Posts.process(id) do
        {:ok, post} -> {:ok, post_summary(post)}
        {:error, :not_found} -> {:error, "Post not found"}
        {:error, reason} -> {:error, format_error(reason)}
      end
    end
  end

  @spec upload_post_images(args()) :: action_result()
  def upload_post_images(args) do
    with {:ok, id} <- require_id(args, :post_id) do
      case Posts.process(id) do
        {:ok, post} ->
          {:ok,
           post_summary(post)
           |> Map.put(:pending_images, post.status == Post.status_pending_images())}

        {:error, :not_found} ->
          {:error, "Post not found"}

        {:error, reason} ->
          {:error, format_error(reason)}
      end
    end
  end

  @spec reprocess_post(args()) :: action_result()
  def reprocess_post(args) do
    with {:ok, id} <- require_id(args, :post_id) do
      case Posts.reprocess(id) do
        {:ok, post} -> {:ok, post_summary(post)}
        {:error, :not_found} -> {:error, "Post not found"}
        {:error, :invalid_id} -> {:error, "Invalid post_id"}
        {:error, reason} -> {:error, format_error(reason)}
      end
    end
  end

  @spec publish_post(args()) :: action_result()
  def publish_post(args) do
    with {:ok, id} <- require_id(args, :post_id) do
      case Posts.publish(id) do
        {:ok, result} -> {:ok, result}
        {:error, :not_found} -> {:error, "Post not found"}
        {:error, reason} -> {:error, format_error(reason)}
      end
    end
  end

  @spec update_post(args()) :: action_result()
  def update_post(args) do
    with {:ok, id} <- require_id(args, :post_id) do
      params =
        string_params(args, [:title, :summary, :content, :language, :hashtags, :categories])

      case Posts.update(id, params) do
        {:ok, post} -> {:ok, post_detail(Rss2Nostr.Posts.get_post(post.id) || post)}
        {:error, :not_found} -> {:error, "Post not found"}
        {:error, :invalid_id} -> {:error, "Invalid post_id"}
        {:error, %Ecto.Changeset{} = changeset} -> {:error, format_changeset(changeset)}
        {:error, reason} -> {:error, format_error(reason)}
      end
    end
  end

  @spec revise_post(args()) :: action_result()
  def revise_post(args) do
    with {:ok, id} <- require_id(args, :post_id) do
      case Posts.revise(id) do
        {:ok, post} -> {:ok, post_summary(post)}
        {:error, :not_found} -> {:error, "Post not found"}
        {:error, :invalid_id} -> {:error, "Invalid post_id"}
        {:error, reason} -> {:error, format_error(reason)}
      end
    end
  end

  @spec delete_post(args()) :: action_result()
  def delete_post(args) do
    with {:ok, id} <- require_id(args, :post_id) do
      case Posts.delete(id) do
        {:ok, post} -> {:ok, %{deleted: true, id: post.id, title: post.title}}
        {:error, :not_found} -> {:error, "Post not found"}
        {:error, :invalid_id} -> {:error, "Invalid post_id"}
      end
    end
  end

  @spec scheduler_status() :: action_result()
  def scheduler_status do
    status = Scheduler.status()

    {:ok,
     Map.put(status, :cleanup_stats, %{
       deleted: Rss2Nostr.Posts.count_draft_cleaned(),
       pending: Rss2Nostr.Posts.count_draft_cleanup_candidates()
     })}
  end

  @spec start_scheduler() :: {:ok, String.t()} | {:error, term()}
  def start_scheduler, do: Scheduler.start()

  @spec stop_scheduler() :: {:ok, String.t()}
  def stop_scheduler, do: Scheduler.stop()

  @spec run_scheduler_task(args()) :: {:ok, String.t()} | {:error, String.t()} | {:error, term()}
  def run_scheduler_task(args) do
    with {:ok, task} <- require_string(args, :task) do
      Scheduler.run_task(task)
    end
  end

  @spec follow_list_status(args()) :: action_result()
  def follow_list_status(args) do
    if truthy?(arg(args, :refresh)), do: FollowList.refresh_sync()

    {:ok, follow_list_status_map(truthy?(arg(args, :include_members)))}
  end

  @spec follow_list_refresh() :: action_result()
  def follow_list_refresh do
    :ok = FollowList.refresh()
    {:ok, follow_list_status_map(false)}
  end

  @spec follow_list_status_map(boolean()) :: map()
  defp follow_list_status_map(include_members?) do
    status = FollowList.status()

    result = %{
      configured: status.configured,
      pubkey: status.pubkey,
      count: status.count,
      fetched_at: status.fetched_at,
      error: status.error,
      refreshing: status.refreshing
    }

    if include_members? do
      Map.put(result, :members, FollowList.members())
    else
      result
    end
  end

  @spec follow_list_member(args()) :: action_result()
  def follow_list_member(args) do
    unless FollowList.configured?() do
      {:error, "Follow list is not configured"}
    else
      with {:ok, pubkey} <- resolve_follow_list_pubkey(args) do
        {:ok,
         %{
           configured: true,
           author_pubkey: pubkey,
           member: FollowList.member?(pubkey)
         }}
      end
    end
  end

  @spec source_detail(Source.t()) :: map()
  defp source_detail(%Source{} = source) do
    options = source.options || %{}

    %{
      id: source.id,
      name: source.name,
      url: source.url,
      type: source.type,
      active: source.active,
      mode: source.mode,
      publish_as: source.publish_as,
      mirror_media: if(Source.mirror_media?(source), do: "blossom", else: "original"),
      language: source.language,
      public: source.public,
      pubkey: source.pubkey,
      author_pubkey: Signer.author_pubkey(source),
      default_post_kind: source.default_post_kind,
      fetch_source_from: source.fetch_source_from,
      staging_hold_minutes: source.staging_hold_minutes || 0,
      notify_pubkey: source.notify_pubkey,
      fixed_hashtags: source.fixed_hashtags || [],
      excluded_hashtags: source.excluded_hashtags || [],
      bunker_configured: present?(source.bunker_connection),
      signing_nsec_configured: Signer.signing_nsec_configured?(source),
      start_guid: options["start_guid"],
      body_selector: options["body_selector"],
      start_at: options["start_at"],
      skip_classes: skip_classes_text(options),
      conversion_rules: options["conversion_rules"] || [],
      publish_after_date: source.publish_after_date,
      options: options,
      follow_list: FollowList.source_membership_map(source)
    }
  end

  @spec skip_classes_text(map()) :: String.t()
  defp skip_classes_text(options) do
    case options["skip_classes"] do
      list when is_list(list) -> Enum.join(list, ", ")
      text when is_binary(text) -> text
      _ -> Composer.default_skip_classes_text()
    end
  end

  @spec post_summary(Post.t()) :: map()
  defp post_summary(%Post{} = post) do
    %{
      id: post.id,
      title: post.title,
      url: post.source_url,
      status: Post.status_name(post.status),
      source_id: post.source_id,
      published_at: post.published_at,
      staged_at: post.staged_at,
      event_id: post.event_id,
      last_error: post.last_error,
      reprocessable: reprocessable?(post),
      publishable: publishable?(post)
    }
  end

  @spec reprocessable?(Post.t()) :: boolean()
  defp reprocessable?(%Post{} = post) do
    post.status in [Post.status_processed(), Post.status_pending_images(), Post.status_error()]
  end

  @spec publishable?(Post.t()) :: boolean()
  defp publishable?(%Post{} = post), do: post.status == Post.status_processed()

  @spec post_detail(Post.t()) :: map()
  defp post_detail(%Post{} = post) do
    post
    |> post_summary()
    |> Map.merge(%{
      summary: post.summary,
      image: post.image,
      language: post.language,
      categories: post.categories,
      content: post.content,
      nostr_address: post.nostr_address
    })
  end

  @spec arg(args(), atom()) :: term()
  defp arg(args, key) when is_atom(key) do
    cond do
      Map.has_key?(args, key) -> Map.get(args, key)
      Map.has_key?(args, to_string(key)) -> Map.get(args, to_string(key))
      true -> nil
    end
  end

  @spec require_string(args(), atom()) :: {:ok, String.t()} | {:error, String.t()}
  defp require_string(args, key) do
    case arg(args, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, "#{key} is required"}
    end
  end

  @spec require_id(args(), atom()) :: {:ok, String.t()} | {:error, String.t()}
  defp require_id(args, key) do
    case arg(args, key) do
      value when is_integer(value) and value > 0 -> {:ok, Integer.to_string(value)}
      value when is_float(value) and value > 0 -> {:ok, value |> trunc() |> Integer.to_string()}
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, "#{key} is required"}
    end
  end

  @spec require_id_list(args(), atom()) :: {:ok, [String.t()]} | {:error, String.t()}
  defp require_id_list(args, key) do
    case arg(args, key) do
      list when is_list(list) and list != [] ->
        {:ok, Enum.map(list, &to_string/1)}

      value when is_binary(value) and value != "" ->
        {:ok, value |> String.split(",") |> Enum.map(&String.trim/1)}

      _ ->
        {:error, "#{key} is required"}
    end
  end

  @spec optional_string(args(), atom()) :: String.t() | nil
  defp optional_string(args, key) do
    case arg(args, key) do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  @spec optional_int(args(), atom(), pos_integer() | nil) :: pos_integer() | nil
  defp optional_int(args, key, default) do
    case arg(args, key) do
      value when is_integer(value) and value > 0 ->
        value

      value when is_float(value) and value > 0 ->
        trunc(value)

      value when is_binary(value) ->
        case Integer.parse(value) do
          {int, ""} when int > 0 -> int
          _ -> default
        end

      nil ->
        default

      _ ->
        default
    end
  end

  @spec string_params(args(), [atom()]) :: map()
  defp string_params(args, keys) do
    Enum.reduce(keys, %{}, fn key, acc ->
      case arg(args, key) do
        nil -> acc
        value -> Map.put(acc, Atom.to_string(key), stringify(value))
      end
    end)
  end

  @spec stringify(term()) :: String.t()
  defp stringify(true), do: "true"
  defp stringify(false), do: "false"
  defp stringify(value) when is_list(value), do: Enum.map_join(value, ",", &to_string/1)
  defp stringify(value), do: to_string(value)

  @spec maybe_kw(keyword(), atom(), term()) :: keyword()
  defp maybe_kw(opts, _key, nil), do: opts
  defp maybe_kw(opts, key, value), do: Keyword.put(opts, key, value)

  @spec status_value(String.t()) :: integer() | String.t()
  defp status_value(name) do
    case name do
      "new" -> Post.status_new()
      "processing" -> Post.status_processing()
      "processed" -> Post.status_processed()
      "staging" -> Post.status_processed()
      "pending_images" -> Post.status_pending_images()
      "published" -> Post.status_published()
      "error" -> Post.status_error()
      _ -> name
    end
  end

  @spec format_changeset(Ecto.Changeset.t()) :: String.t()
  defp format_changeset(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join("; ", fn {field, msgs} -> "#{field}: #{Enum.join(msgs, ", ")}" end)
  end

  @spec format_error(term()) :: String.t()
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)

  @spec present?(term()) :: boolean()
  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: false

  @spec truthy?(term()) :: boolean()
  defp truthy?(value), do: value in [true, "true", "1", 1]

  @spec resolve_follow_list_pubkey(args()) :: {:ok, String.t()} | {:error, String.t()}
  defp resolve_follow_list_pubkey(args) do
    pubkey = arg(args, :pubkey)
    source_id = arg(args, :source_id)

    cond do
      is_binary(pubkey) and pubkey != "" ->
        case Rss2Nostr.Nostr.Keys.parse_public_key(pubkey) do
          {:ok, hex} -> {:ok, hex}
          {:error, _} -> {:error, "Invalid pubkey"}
        end

      not is_nil(source_id) ->
        with {:ok, id} <- require_id(args, :source_id),
             {:ok, source} <- Sources.get(id) do
          case Signer.author_pubkey(source) do
            hex when is_binary(hex) -> {:ok, hex}
            _ -> {:error, "Source has no resolved author pubkey"}
          end
        end

      true ->
        {:error, "pubkey or source_id is required"}
    end
  end
end
