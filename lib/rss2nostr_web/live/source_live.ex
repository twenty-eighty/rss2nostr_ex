defmodule Rss2NostrWeb.SourceLive do
  @moduledoc false

  use Rss2NostrWeb, :live_view

  import Rss2NostrWeb.SourceComponents

  alias Rss2Nostr.Posts
  alias Rss2Nostr.Processing.{BodySchema, Composer}
  alias Rss2Nostr.Web.API.Posts, as: PostsAPI
  alias Rss2Nostr.Web.API.Sources, as: SourcesAPI

  @tabs ~w(feed compose articles publishing)

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case SourcesAPI.get(id) do
      {:ok, source} ->
        {:ok,
         socket
         |> assign(:active_nav, "sources")
         |> assign(:source, source)
         |> assign(:tab, "compose")
         |> assign(:errors, %{})
         |> assign(:busy, false)
         |> assign(:selected_ids, MapSet.new())
         |> assign(:posts, [])
         |> assign(:feed_items, :not_loaded)
         |> assign(:feed_status, nil)
         |> assign(:preview, nil)
         |> assign(:preview_status, nil)
         |> assign(:preview_tab, "rendered")
         |> assign(:show_split, false)
         |> assign(:compose, compose_form(source))
         |> assign(:feed, feed_form(source))
         |> assign(:publishing, publishing_form(source))}

      {:error, _} ->
        {:ok,
         socket
         |> assign(:source, nil)
         |> put_flash(:error, "Source not found")
         |> redirect(to: "/sources")}
    end
  end

  @impl true
  def handle_params(_params, _uri, %{assigns: %{source: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_params(params, _uri, socket) do
    tab = normalize_tab(params["tab"])
    source = socket.assigns.source

    socket =
      socket
      |> assign(:tab, tab)
      |> assign(:wide, tab == "compose")
      |> assign(:page_title, source.name)
      |> apply_query_flash(params)

    socket =
      case tab do
        "articles" -> assign_posts(socket)
        "feed" -> maybe_load_feed_items(socket)
        "compose" -> maybe_load_feed_items(socket)
        _ -> socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("save_feed", params, socket) do
    save_source(socket, Map.put(params, "tab", "feed"), :feed)
  end

  def handle_event("save_compose", params, socket) do
    params = Map.merge(socket.assigns.compose, params)
    save_source(socket, Map.put(params, "tab", "compose"), :compose)
  end

  def handle_event("save_publishing", params, socket) do
    save_source(socket, Map.put(params, "tab", "publishing"), :publishing)
  end

  def handle_event("publishing_changed", params, socket) do
    {:noreply, assign(socket, :publishing, merge_form(socket.assigns.publishing, params))}
  end

  def handle_event("save_feed_start", %{"start_guid" => guid} = params, socket) do
    published_at =
      case Enum.find(feed_item_list(socket.assigns.feed_items), &(&1.guid == guid)) do
        %{published_at: published} -> published
        _ -> ""
      end

    feed =
      socket.assigns.feed
      |> Map.put("start_guid", guid)
      |> Map.put("start_published_at", published_at || "")

    {:noreply, assign(socket, :feed, merge_form(feed, params))}
  end

  def handle_event("set_mode", %{"mode" => mode}, socket) when mode in ["setup", "automated"] do
    save_source(socket, %{"mode" => mode, "tab" => socket.assigns.tab}, nil)
  end

  def handle_event("duplicate", _params, socket) do
    case SourcesAPI.duplicate(socket.assigns.source) do
      {:ok, source} ->
        {:noreply, push_navigate(socket, to: "/sources/#{source.id}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, format_update_error(reason))}
    end
  end

  def handle_event("compose_changed", params, socket) do
    compose = merge_form(socket.assigns.compose, params)

    compose =
      if params["_target"] == ["body_preset"] do
        Map.put(compose, "body_selector", params["body_preset"] || "")
      else
        compose
      end

    {:noreply,
     socket
     |> assign(:compose, compose)
     |> maybe_preview()}
  end

  def handle_event("pick_article", %{"guid" => guid}, socket) do
    compose = Map.put(socket.assigns.compose, "guid", guid)

    {:noreply,
     socket
     |> assign(:compose, compose)
     |> maybe_preview()}
  end

  def handle_event("pick_region", %{"selector" => selector}, socket) do
    compose =
      socket.assigns.compose
      |> Map.put("body_selector", selector)
      |> Map.put("start_at", "")

    {:noreply,
     socket
     |> assign(:compose, compose)
     |> maybe_preview()}
  end

  def handle_event("pick_start", %{"xpath" => xpath}, socket) do
    compose = Map.put(socket.assigns.compose, "start_at", xpath)

    {:noreply,
     socket
     |> assign(:compose, compose)
     |> maybe_preview()}
  end

  def handle_event("set_preview_tab", %{"tab" => tab}, socket)
      when tab in ["rendered", "source", "event"] do
    {:noreply, assign(socket, :preview_tab, tab)}
  end

  def handle_event("toggle_split", %{"value" => value}, socket) do
    {:noreply, assign(socket, :show_split, value == "true" or value == "on")}
  end

  def handle_event("toggle_split", _params, socket) do
    {:noreply, assign(socket, :show_split, false)}
  end

  def handle_event("refresh_preview", _params, socket) do
    {:noreply, maybe_preview(socket)}
  end

  def handle_event("import", _params, socket) do
    source = socket.assigns.source

    {:noreply,
     socket
     |> assign(:busy, true)
     |> start_async(:import, fn -> SourcesAPI.import_now(source) end)}
  end

  def handle_event("toggle_post", %{"id" => id}, socket) do
    id = String.to_integer(id)
    selected = socket.assigns.selected_ids

    selected =
      if MapSet.member?(selected, id) do
        MapSet.delete(selected, id)
      else
        MapSet.put(selected, id)
      end

    {:noreply, assign(socket, :selected_ids, selected)}
  end

  def handle_event("toggle_all", %{"checked" => "true"}, socket) do
    ids =
      socket.assigns.posts
      |> Enum.filter(&reprocessable?/1)
      |> Enum.map(& &1.id)
      |> MapSet.new()

    {:noreply, assign(socket, :selected_ids, ids)}
  end

  def handle_event("toggle_all", _params, socket) do
    {:noreply, assign(socket, :selected_ids, MapSet.new())}
  end

  def handle_event("publish_selected", _params, socket) do
    ids = selected_list(socket)
    source = socket.assigns.source

    {:noreply,
     socket
     |> assign(:busy, true)
     |> start_async(:publish, fn ->
       SourcesAPI.publish_selected(source, %{"post_ids" => ids})
     end)}
  end

  def handle_event("reprocess_selected", _params, socket) do
    ids = selected_list(socket)
    source = socket.assigns.source

    {:noreply,
     socket
     |> assign(:busy, true)
     |> start_async(:reprocess, fn ->
       SourcesAPI.reprocess_selected(source, %{"post_ids" => ids})
     end)}
  end

  def handle_event("upload_images", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(:busy, true)
     |> start_async(:upload, fn -> PostsAPI.process(id) end)}
  end

  @impl true
  def handle_async(:feed_items, {:ok, {:ok, result}}, socket) do
    items = result[:items] || result["items"] || []
    socket = assign(socket, feed_items: items, feed_status: nil)

    socket =
      if socket.assigns.tab == "compose" and socket.assigns.compose["guid"] in [nil, ""] do
        case items do
          [%{guid: guid} | _] ->
            compose = Map.put(socket.assigns.compose, "guid", guid)
            socket |> assign(:compose, compose) |> maybe_preview()

          _ ->
            socket
        end
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_async(:feed_items, {:ok, {:error, reason}}, socket) do
    {:noreply, assign(socket, feed_items: [], feed_status: to_string(reason))}
  end

  def handle_async(:feed_items, {:exit, reason}, socket) do
    {:noreply, assign(socket, feed_items: [], feed_status: Exception.format_exit(reason))}
  end

  def handle_async(:preview, {:ok, {:ok, result}}, socket) do
    compose =
      if socket.assigns.compose["body_selector"] in [nil, ""] and
           result.body_selector not in [nil, ""] do
        Map.put(socket.assigns.compose, "body_selector", result.body_selector)
      else
        socket.assigns.compose
      end

    {:noreply,
     socket
     |> assign(:compose, compose)
     |> assign(:preview, result)
     |> assign(:preview_status, nil)
     |> assign(:show_split, false)}
  end

  def handle_async(:preview, {:ok, {:error, reason}}, socket) do
    {:noreply, assign(socket, preview: nil, preview_status: to_string(reason))}
  end

  def handle_async(:preview, {:exit, reason}, socket) do
    {:noreply, assign(socket, preview: nil, preview_status: Exception.format_exit(reason))}
  end

  def handle_async(:import, {:ok, {:ok, result}}, socket) do
    {:noreply,
     socket
     |> assign(:busy, false)
     |> put_flash(:info, import_notice(result))
     |> assign_posts()}
  end

  def handle_async(:import, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:busy, false)
     |> put_flash(:error, format_update_error(reason))}
  end

  def handle_async(:import, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:busy, false)
     |> put_flash(:error, Exception.format_exit(reason))}
  end

  def handle_async(:publish, {:ok, {:ok, result}}, socket) do
    {kind, message} = publish_notice(result)

    {:noreply,
     socket
     |> assign(:busy, false)
     |> assign(:selected_ids, MapSet.new())
     |> put_flash(kind, message)
     |> assign_posts()}
  end

  def handle_async(:publish, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:busy, false)
     |> put_flash(:error, format_update_error(reason))}
  end

  def handle_async(:publish, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:busy, false)
     |> put_flash(:error, Exception.format_exit(reason))}
  end

  def handle_async(:reprocess, {:ok, {:ok, result}}, socket) do
    {:noreply,
     socket
     |> assign(:busy, false)
     |> assign(:selected_ids, MapSet.new())
     |> put_flash(:info, reprocess_notice(result))
     |> assign_posts()}
  end

  def handle_async(:reprocess, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:busy, false)
     |> put_flash(:error, format_update_error(reason))}
  end

  def handle_async(:reprocess, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:busy, false)
     |> put_flash(:error, Exception.format_exit(reason))}
  end

  def handle_async(:upload, {:ok, {:ok, _post}}, socket) do
    {:noreply, socket |> assign(:busy, false) |> assign_posts()}
  end

  def handle_async(:upload, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:busy, false)
     |> put_flash(:error, format_update_error(reason))}
  end

  def handle_async(:upload, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:busy, false)
     |> put_flash(:error, Exception.format_exit(reason))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="page-header">
      <h1>{@source.name}</h1>
      <div>
        <.mode_badge source={@source} tab={@tab} />
        <span class={"badge #{relay_badge_class(target_for(@source))}"}>
          {relay_target_label(target_for(@source))}
        </span>
        <button type="button" class="btn btn-secondary" phx-click="duplicate">Duplicate</button>
        <a href="/sources" class="btn btn-secondary">Back to sources</a>
      </div>
    </div>

    <nav class="source-tabs" aria-label="Source sections">
      <.tab_link source={@source} name="feed" label="Feed" current={@tab} />
      <.tab_link source={@source} name="compose" label="Compose" current={@tab} />
      <.tab_link source={@source} name="articles" label="Articles" current={@tab} />
      <.tab_link source={@source} name="publishing" label="Publishing" current={@tab} />
    </nav>

    <.feed_tab
      :if={@tab == "feed"}
      source={@source}
      feed={@feed}
      errors={@errors}
      feed_items={@feed_items}
      feed_status={@feed_status}
    />
    <.compose_tab
      :if={@tab == "compose"}
      source={@source}
      compose={@compose}
      errors={@errors}
      feed_items={@feed_items}
      feed_status={@feed_status}
      preview={@preview}
      preview_status={@preview_status}
      preview_tab={@preview_tab}
      show_split={@show_split}
    />
    <.articles_tab
      :if={@tab == "articles"}
      source={@source}
      posts={@posts}
      selected_ids={@selected_ids}
      busy={@busy}
    />
    <.publishing_tab
      :if={@tab == "publishing"}
      source={@source}
      publishing={@publishing}
      errors={@errors}
    />
    """
  end

  defp save_source(socket, params, form_key) do
    source = socket.assigns.source

    case SourcesAPI.update(source, params) do
      {:ok, updated} ->
        socket =
          socket
          |> assign(:source, updated)
          |> assign(:errors, %{})
          |> assign(:compose, compose_form(updated, socket.assigns.compose))
          |> assign(:feed, feed_form(updated))
          |> assign(:publishing, publishing_form(updated))
          |> put_flash(:info, "Settings saved.")

        socket = if form_key == :compose, do: maybe_preview(socket), else: socket
        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        socket =
          socket
          |> assign(:errors, changeset_errors(changeset))
          |> maybe_assign_form(form_key, params)

        {:noreply, put_flash(socket, :error, format_update_error(changeset))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, format_update_error(reason))}
    end
  end

  defp maybe_assign_form(socket, :feed, params),
    do: assign(socket, :feed, merge_form(socket.assigns.feed, params))

  defp maybe_assign_form(socket, :compose, params),
    do: assign(socket, :compose, merge_form(socket.assigns.compose, params))

  defp maybe_assign_form(socket, :publishing, params),
    do: assign(socket, :publishing, merge_form(socket.assigns.publishing, params))

  defp maybe_assign_form(socket, _, _), do: socket

  defp assign_posts(socket) do
    posts = Posts.list_posts_for_source(socket.assigns.source.id, limit: 100)
    assign(socket, :posts, posts)
  end

  defp maybe_load_feed_items(socket) do
    if socket.assigns.feed_items == :not_loaded and connected?(socket) do
      url = socket.assigns.source.url

      socket
      |> assign(:feed_status, "Loading articles…")
      |> start_async(:feed_items, fn -> SourcesAPI.preview(%{"url" => url}) end)
    else
      socket
    end
  end

  defp maybe_preview(socket) do
    guid = socket.assigns.compose["guid"]

    if guid in [nil, ""] do
      assign(socket, preview: nil, preview_status: "Pick an article to preview the Markdown.")
    else
      params = preview_params(socket)

      socket
      |> assign(:preview_status, "Building preview…")
      |> cancel_async(:preview)
      |> start_async(:preview, fn -> Composer.preview(params) end)
    end
  end

  defp preview_params(socket) do
    source = socket.assigns.source
    compose = socket.assigns.compose

    %{
      "url" => source.url,
      "type" => source.type,
      "source_id" => source.id,
      "guid" => compose["guid"],
      "fetch_source_from" => compose["fetch_source_from"],
      "body_selector" => compose["body_selector"],
      "start_at" => compose["start_at"],
      "skip_classes" => compose["skip_classes"],
      "excluded_hashtags" => compose["excluded_hashtags"],
      "language" => source.language
    }
  end

  defp compose_form(source, existing \\ %{}) do
    %{
      "guid" => existing["guid"] || "",
      "fetch_source_from" => source.fetch_source_from || "fetch_from_url",
      "body_selector" =>
        option(source, "body_selector") || BodySchema.selector_for_url(source.url) || "",
      "start_at" => option(source, "start_at") || "",
      "skip_classes" => skip_classes_text(source),
      "excluded_hashtags" => join_tags(source.excluded_hashtags)
    }
  end

  defp feed_form(source) do
    %{
      "name" => source.name,
      "url" => source.url,
      "language" => source.language || "de",
      "start_guid" => option(source, "start_guid") || "",
      "start_published_at" => datetime_value(source.publish_after_date)
    }
  end

  defp publishing_form(source) do
    %{
      "publish_as" => source.publish_as || "draft",
      "mirror_media" => option(source, "mirror_media") || "blossom",
      "pubkey" => source.pubkey || "",
      "bunker_connection" => source.bunker_connection || "",
      "fixed_hashtags" => join_tags(source.fixed_hashtags),
      "excluded_hashtags" => join_tags(source.excluded_hashtags),
      "staging_hold_minutes" => to_string(source.staging_hold_minutes || 0),
      "notify_pubkey" => source.notify_pubkey || ""
    }
  end

  defp merge_form(form, params) do
    Enum.reduce(form, form, fn {key, _}, acc ->
      case Map.fetch(params, key) do
        {:ok, value} -> Map.put(acc, key, value)
        :error -> acc
      end
    end)
  end

  defp normalize_tab(tab) when tab in @tabs, do: tab
  defp normalize_tab(_), do: "compose"

  defp selected_list(socket), do: MapSet.to_list(socket.assigns.selected_ids)

  defp feed_item_list(:not_loaded), do: []
  defp feed_item_list(items) when is_list(items), do: items
end
