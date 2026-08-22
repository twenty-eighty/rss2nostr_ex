defmodule Rss2Nostr.MCP.Actions do
  @moduledoc false

  alias Rss2Nostr.Nostr.Signer
  alias Rss2Nostr.Posts
  alias Rss2Nostr.Posts.Post
  alias Rss2Nostr.Sources.Source
  alias Rss2Nostr.Web.API.{Posts, Scheduler, Settings, Sources, Status}

  def get_status, do: {:ok, Status.overview()}
  def get_settings, do: {:ok, Settings.get()}

  def list_sources do
    {:ok, %{sources: Sources.list()}}
  end

  def get_source(args) do
    with {:ok, id} <- require_id(args, :source_id) do
      case Sources.get(id) do
        {:ok, source} -> {:ok, source_detail(source)}
        {:error, :not_found} -> {:error, "Source not found"}
        {:error, :invalid_id} -> {:error, "Invalid source_id"}
      end
    end
  end

  def discover_feeds(args) do
    with {:ok, url} <- require_string(args, :url) do
      Sources.discover(%{"url" => url})
    end
  end

  def preview_feed(args) do
    with {:ok, url} <- require_string(args, :url) do
      Sources.preview(%{"url" => url})
    end
  end

  def preview_compose(args) do
    params = string_params(args, ~w(url guid type body_selector start_at skip_classes language)a)

    params =
      case arg(args, :source_id) do
        nil -> params
        id -> Map.put(params, "source_id", to_string(id))
      end

    Sources.compose_preview(params)
  end

  def add_source(args) do
    with {:ok, name} <- require_string(args, :name),
         {:ok, url} <- require_string(args, :url) do
      params =
        string_params(args, [
          :type,
          :language,
          :publish_as,
          :mirror_media,
          :pubkey,
          :signing_nsec,
          :bunker_connection,
          :fetch_source_from,
          :body_selector,
          :start_at,
          :skip_classes,
          :start_published_at,
          :staging_hold_minutes,
          :notify_pubkey,
          :fixed_hashtags
        ])
        |> Map.merge(%{"name" => name, "url" => url})

      case Sources.create(params) do
        {:ok, source} -> {:ok, source_detail(source)}
        {:error, changeset} -> {:error, format_changeset(changeset)}
      end
    end
  end

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
          :pubkey,
          :signing_nsec,
          :bunker_connection,
          :fetch_source_from,
          :body_selector,
          :start_at,
          :skip_classes,
          :start_published_at,
          :staging_hold_minutes,
          :notify_pubkey,
          :fixed_hashtags
        ])

      case Sources.update(id, params) do
        {:ok, source} -> {:ok, source_detail(source)}
        {:error, :not_found} -> {:error, "Source not found"}
        {:error, :invalid_id} -> {:error, "Invalid source_id"}
        {:error, changeset} -> {:error, format_changeset(changeset)}
      end
    end
  end

  def toggle_source(args) do
    with {:ok, id} <- require_id(args, :source_id) do
      case Sources.toggle(id) do
        {:ok, source} -> {:ok, source_detail(source)}
        {:error, :not_found} -> {:error, "Source not found"}
        {:error, :invalid_id} -> {:error, "Invalid source_id"}
        {:error, changeset} -> {:error, format_changeset(changeset)}
      end
    end
  end

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

  def delete_source(args) do
    with {:ok, id} <- require_id(args, :source_id) do
      case Sources.delete(id) do
        {:ok, source} -> {:ok, %{deleted: true, id: source.id, name: source.name}}
        {:error, :not_found} -> {:error, "Source not found"}
        {:error, :invalid_id} -> {:error, "Invalid source_id"}
      end
    end
  end

  def import_source(args) do
    with {:ok, id} <- require_id(args, :source_id) do
      case Sources.import_now(id) do
        {:ok, result} -> {:ok, result}
        {:error, :not_found} -> {:error, "Source not found"}
        {:error, reason} -> {:error, inspect(reason)}
      end
    end
  end

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

  def process_post(args) do
    with {:ok, id} <- require_id(args, :post_id) do
      case Posts.process(id) do
        {:ok, post} -> {:ok, post_summary(post)}
        {:error, :not_found} -> {:error, "Post not found"}
        {:error, reason} -> {:error, format_error(reason)}
      end
    end
  end

  def publish_post(args) do
    with {:ok, id} <- require_id(args, :post_id) do
      case Posts.publish(id) do
        {:ok, result} -> {:ok, result}
        {:error, :not_found} -> {:error, "Post not found"}
        {:error, reason} -> {:error, format_error(reason)}
      end
    end
  end

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

  def delete_post(args) do
    with {:ok, id} <- require_id(args, :post_id) do
      case Posts.delete(id) do
        {:ok, post} -> {:ok, %{deleted: true, id: post.id, title: post.title}}
        {:error, :not_found} -> {:error, "Post not found"}
        {:error, :invalid_id} -> {:error, "Invalid post_id"}
      end
    end
  end

  def scheduler_status, do: {:ok, Scheduler.status()}
  def start_scheduler, do: Scheduler.start()
  def stop_scheduler, do: Scheduler.stop()

  def run_scheduler_task(args) do
    with {:ok, task} <- require_string(args, :task) do
      Scheduler.run_task(task)
    end
  end

  defp source_detail(%Source{} = source) do
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
      bunker_configured: present?(source.bunker_connection),
      signing_nsec_configured: Signer.signing_nsec_configured?(source),
      options: source.options || %{}
    }
  end

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
      last_error: post.last_error
    }
  end

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

  defp arg(args, key) when is_atom(key) do
    Map.get(args, key) || Map.get(args, Atom.to_string(key))
  end

  defp require_string(args, key) do
    case arg(args, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, "#{key} is required"}
    end
  end

  defp require_id(args, key) do
    case arg(args, key) do
      value when is_integer(value) and value > 0 -> {:ok, Integer.to_string(value)}
      value when is_float(value) and value > 0 -> {:ok, value |> trunc() |> Integer.to_string()}
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, "#{key} is required"}
    end
  end

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

  defp optional_string(args, key) do
    case arg(args, key) do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

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

  defp string_params(args, keys) do
    Enum.reduce(keys, %{}, fn key, acc ->
      case arg(args, key) do
        nil -> acc
        value -> Map.put(acc, Atom.to_string(key), stringify(value))
      end
    end)
  end

  defp stringify(true), do: "true"
  defp stringify(false), do: "false"
  defp stringify(value) when is_list(value), do: Enum.map_join(value, ",", &to_string/1)
  defp stringify(value), do: to_string(value)

  defp maybe_kw(opts, _key, nil), do: opts
  defp maybe_kw(opts, key, value), do: Keyword.put(opts, key, value)

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

  defp format_changeset(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join("; ", fn {field, msgs} -> "#{field}: #{Enum.join(msgs, ", ")}" end)
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: false
end
