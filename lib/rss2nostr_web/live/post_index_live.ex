defmodule Rss2NostrWeb.PostIndexLive do
  @moduledoc false

  use Rss2NostrWeb, :live_view

  alias Rss2Nostr.Posts
  alias Rss2Nostr.Posts.Post
  alias Rss2Nostr.Sources
  alias Rss2Nostr.Web.API.Posts, as: PostsAPI

  @per_page 20

  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()} | {:ok, Phoenix.LiveView.Socket.t(), keyword()}
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Posts")
     |> assign(:active_nav, "posts")
     |> assign(:busy, false)
     |> assign(:selected_ids, MapSet.new())}
  end

  @impl true
  @spec handle_params(map(), String.t(), Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_params(params, _uri, socket) do
    status = blank_to_nil(params["status"])
    source_id = parse_source_id(params["source_id"])
    q = blank_to_nil(params["q"])
    page = parse_page(params["page"])

    {:noreply,
     socket
     |> apply_query_flash(params)
     |> assign(:status, status)
     |> assign(:source_id, source_id)
     |> assign(:q, q)
     |> assign(:page, page)
     |> assign(:selected_ids, MapSet.new())
     |> assign_posts()}
  end

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("filter", params, socket) do
    {:noreply,
     push_patch(socket,
       to:
         posts_path(
           status: socket.assigns.status,
           source_id: blank_to_nil(params["source_id"]),
           q: blank_to_nil(params["q"]),
           page: 1
         )
     )}
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

    {:noreply,
     socket
     |> assign(:selected_ids, selected)
     |> assign_selection_flags()}
  end

  def handle_event("toggle_all", %{"checked" => "true"}, socket) do
    {:noreply,
     socket
     |> assign(:selected_ids, MapSet.new(socket.assigns.selectable_ids))
     |> assign_selection_flags()}
  end

  def handle_event("toggle_all", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_ids, MapSet.new())
     |> assign_selection_flags()}
  end

  def handle_event("publish_selected", _params, socket) do
    ids = MapSet.to_list(socket.assigns.selected_ids)

    {:noreply,
     socket
     |> assign(:busy, true)
     |> start_async(:publish, fn -> PostsAPI.publish_selected(%{"post_ids" => ids}) end)}
  end

  def handle_event("reprocess_selected", _params, socket) do
    ids = MapSet.to_list(socket.assigns.selected_ids)

    {:noreply,
     socket
     |> assign(:busy, true)
     |> start_async(:reprocess, fn -> PostsAPI.reprocess_selected(%{"post_ids" => ids}) end)}
  end

  def handle_event("process_post", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(:busy, true)
     |> start_async(:one, fn -> PostsAPI.process(id) end)}
  end

  def handle_event("publish_post", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(:busy, true)
     |> start_async(:one_publish, fn -> PostsAPI.publish(id) end)}
  end

  @impl true
  @spec handle_async(atom(), term(), Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
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
    {:noreply, socket |> assign(:busy, false) |> put_flash(:error, format_update_error(reason))}
  end

  def handle_async(:publish, {:exit, reason}, socket) do
    {:noreply, socket |> assign(:busy, false) |> put_flash(:error, Exception.format_exit(reason))}
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
    {:noreply, socket |> assign(:busy, false) |> put_flash(:error, format_update_error(reason))}
  end

  def handle_async(:reprocess, {:exit, reason}, socket) do
    {:noreply, socket |> assign(:busy, false) |> put_flash(:error, Exception.format_exit(reason))}
  end

  def handle_async(:one, {:ok, {:ok, _post}}, socket) do
    {:noreply, socket |> assign(:busy, false) |> assign_posts()}
  end

  def handle_async(:one, {:ok, {:error, reason}}, socket) do
    {:noreply, socket |> assign(:busy, false) |> put_flash(:error, format_update_error(reason))}
  end

  def handle_async(:one, {:exit, reason}, socket) do
    {:noreply, socket |> assign(:busy, false) |> put_flash(:error, Exception.format_exit(reason))}
  end

  def handle_async(:one_publish, {:ok, {:ok, result}}, socket) do
    {kind, message} = publish_notice(normalize_one_publish(result))

    {:noreply,
     socket
     |> assign(:busy, false)
     |> put_flash(kind, message)
     |> assign_posts()}
  end

  def handle_async(:one_publish, {:ok, {:error, reason}}, socket) do
    {:noreply, socket |> assign(:busy, false) |> put_flash(:error, format_update_error(reason))}
  end

  def handle_async(:one_publish, {:exit, reason}, socket) do
    {:noreply, socket |> assign(:busy, false) |> put_flash(:error, Exception.format_exit(reason))}
  end

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div class="page-header">
      <h1>Posts</h1>
    </div>

    <div class="filter-bar">
      <.link
        patch={posts_path(status: nil, source_id: @source_id, q: @q)}
        class={["btn btn-small", is_nil(@status) && "btn-active"]}
      >
        All
      </.link>
      <.link
        patch={posts_path(status: "0", source_id: @source_id, q: @q)}
        class={["btn btn-small", @status == "0" && "btn-active"]}
      >
        New
      </.link>
      <.link
        patch={posts_path(status: "9", source_id: @source_id, q: @q)}
        class={["btn btn-small", @status == "9" && "btn-active"]}
      >
        Pending images
      </.link>
      <.link
        patch={posts_path(status: "2", source_id: @source_id, q: @q)}
        class={["btn btn-small", @status == "2" && "btn-active"]}
      >
        Staging
      </.link>
      <.link
        patch={posts_path(status: "6", source_id: @source_id, q: @q)}
        class={["btn btn-small", @status == "6" && "btn-active"]}
      >
        Published
      </.link>
      <form phx-change="filter" phx-submit="filter" class="filter-source">
        <label for="source_id">Source</label>
        <select id="source_id" name="source_id">
          <option value="">All sources</option>
          <option :for={source <- @sources} value={source.id} selected={source.id == @source_id}>
            {source.name}
          </option>
        </select>
        <label for="q">Contains</label>
        <input
          type="search"
          id="q"
          name="q"
          value={@q}
          placeholder="Filter articles"
          phx-debounce="400"
        />
        <button type="submit" class="btn btn-small">Apply</button>
      </form>
    </div>

    <div class="article-toolbar">
      <button
        type="button"
        class="btn btn-primary"
        phx-click="publish_selected"
        disabled={@busy or not @publishable?}
      >
        Publish selected
      </button>
      <button
        type="button"
        class="btn btn-secondary"
        phx-click="reprocess_selected"
        disabled={@busy or not @selectable?}
      >
        Reprocess selected
      </button>
      <span class="article-selection-count">
        {MapSet.size(@selected_ids)} selected
      </span>
    </div>
    <p class="help-text">
      Select all includes matching articles, not only this page. Staging articles can be published;
      pending-images articles can be reprocessed. Relays come from each source: drafts use the draft list,
      articles use public or test from the source flag.
    </p>

    <table class="table">
      <thead>
        <tr>
          <th class="article-select">
            <input
              type="checkbox"
              id="select-all-posts"
              aria-label="Select all filtered articles"
              phx-click="toggle_all"
              phx-value-checked={to_string(not @all_selected?)}
              checked={@all_selected?}
              disabled={@selectable_ids == []}
            />
          </th>
          <th>Title</th>
          <th>Status</th>
          <th>Source</th>
          <th>Published</th>
          <th>Actions</th>
        </tr>
      </thead>
      <tbody>
        <%= if @posts == [] do %>
          <tr>
            <td colspan="6" class="empty-state">No posts found.</td>
          </tr>
        <% else %>
          <tr :for={post <- @posts} id={"post-#{post.id}"}>
            <td class="article-select">
              <input
                :if={reprocessable?(post)}
                type="checkbox"
                name="post_ids[]"
                value={post.id}
                data-publishable={to_string(publishable?(post))}
                checked={MapSet.member?(@selected_ids, post.id)}
                phx-click="toggle_post"
                phx-value-id={post.id}
              />
            </td>
            <td>
              <a href={"/posts/#{post.id}?return_to=#{URI.encode_www_form(@return_to)}"}>
                {truncate(post.title, 60)}
              </a>
            </td>
            <td><.status_badge status={post.status} /></td>
            <td>{truncate(post.source_url, 40)}</td>
            <td>{format_datetime(post.published_at)}</td>
            <td class="actions">
              <button
                :if={post.status == Post.status_new()}
                type="button"
                class="btn btn-small"
                phx-click="process_post"
                phx-value-id={post.id}
                disabled={@busy}
              >
                Process
              </button>
              <button
                :if={post.status == Post.status_pending_images()}
                type="button"
                class="btn btn-small"
                phx-click="process_post"
                phx-value-id={post.id}
                disabled={@busy}
              >
                Upload images
              </button>
              <button
                :if={post.status == Post.status_processed()}
                type="button"
                class="btn btn-small"
                phx-click="publish_post"
                phx-value-id={post.id}
                disabled={@busy}
              >
                Export
              </button>
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>

    <div :if={@total_pages > 1} class="pagination">
      <.link
        :if={@page > 1}
        patch={posts_path(status: @status, source_id: @source_id, q: @q, page: @page - 1)}
        class="btn btn-small"
      >
        ← Previous
      </.link>
      <span>Page {@page} of {@total_pages}</span>
      <.link
        :if={@page < @total_pages}
        patch={posts_path(status: @status, source_id: @source_id, q: @q, page: @page + 1)}
        class="btn btn-small"
      >
        Next →
      </.link>
    </div>
    """
  end

  @spec assign_posts(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp assign_posts(socket) do
    status = socket.assigns.status
    source_id = socket.assigns.source_id
    q = socket.assigns.q
    page = socket.assigns.page

    filter = [status: status, source_id: source_id, q: q]
    total = Posts.count_posts(filter)
    total_pages = total_pages(total, @per_page)
    page = min(page, total_pages)

    posts =
      Posts.list_posts(
        Keyword.merge(filter,
          limit: @per_page,
          offset: (page - 1) * @per_page
        )
      )

    selectable_ids = selectable_post_ids(status, source_id, q)
    publishable_ids = MapSet.new(publishable_post_ids(status, source_id, q))

    socket
    |> assign(:posts, posts)
    |> assign(:page, page)
    |> assign(:total, total)
    |> assign(:total_pages, total_pages)
    |> assign(:sources, Enum.sort_by(Sources.list_sources(), & &1.name))
    |> assign(:per_page, @per_page)
    |> assign(:selectable_ids, selectable_ids)
    |> assign(:publishable_ids, publishable_ids)
    |> assign(:return_to, posts_path(status: status, source_id: source_id, q: q, page: page))
    |> assign_selection_flags()
  end

  @spec total_pages(non_neg_integer(), pos_integer()) :: pos_integer()
  defp total_pages(total, _per_page) when total <= 0, do: 1
  defp total_pages(total, per_page), do: div(total + per_page - 1, per_page)

  @spec assign_selection_flags(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp assign_selection_flags(socket) do
    selected = socket.assigns.selected_ids
    selectable_ids = socket.assigns.selectable_ids
    publishable_ids = socket.assigns.publishable_ids

    socket
    |> assign(:selectable?, selectable_ids != [] and MapSet.size(selected) > 0)
    |> assign(
      :publishable?,
      Enum.any?(selected, &MapSet.member?(publishable_ids, &1))
    )
    |> assign(
      :all_selected?,
      selectable_ids != [] and Enum.all?(selectable_ids, &MapSet.member?(selected, &1))
    )
  end

  @spec selectable_post_ids(String.t() | nil, integer() | nil, String.t() | nil) :: [integer()]
  defp selectable_post_ids(status_filter, source_id, q) do
    cond do
      status_filter in [nil, ""] ->
        post_ids_for(Post.status_processed(), source_id, q) ++
          post_ids_for(Post.status_pending_images(), source_id, q)

      status_filter == "2" ->
        post_ids_for(Post.status_processed(), source_id, q)

      status_filter == "9" ->
        post_ids_for(Post.status_pending_images(), source_id, q)

      true ->
        []
    end
  end

  @spec publishable_post_ids(String.t() | nil, integer() | nil, String.t() | nil) :: [integer()]
  defp publishable_post_ids(status_filter, source_id, q) do
    if status_filter in [nil, "", "2"] do
      post_ids_for(Post.status_processed(), source_id, q)
    else
      []
    end
  end

  @spec post_ids_for(integer(), integer() | nil, String.t() | nil) :: [integer()]
  defp post_ids_for(status, source_id, q) do
    Posts.list_posts(status: status, source_id: source_id, q: q, limit: 5_000)
    |> Enum.map(& &1.id)
  end

  @spec normalize_one_publish(map()) :: map()
  defp normalize_one_publish(result) when is_map(result) do
    Map.merge(%{published: 1, failed: 0, errors: []}, result)
  end

  @spec blank_to_nil(term()) :: term()
  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  @spec parse_source_id(String.t() | nil) :: integer() | nil
  defp parse_source_id(nil), do: nil
  defp parse_source_id(""), do: nil

  defp parse_source_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> int
      _ -> nil
    end
  end

  @spec parse_page(term()) :: pos_integer()
  defp parse_page(nil), do: 1

  defp parse_page(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> int
      _ -> 1
    end
  end

  defp parse_page(_), do: 1
end
