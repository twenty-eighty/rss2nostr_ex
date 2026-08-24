defmodule Rss2NostrWeb.SourceIndexLive do
  @moduledoc false

  use Rss2NostrWeb, :live_view

  alias Rss2Nostr.Sources
  alias Rss2Nostr.Web.API.Sources, as: SourcesAPI

  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()} | {:ok, Phoenix.LiveView.Socket.t(), keyword()}
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Sources")
     |> assign(:active_nav, "sources")
     |> assign_sources()}
  end

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("toggle", %{"id" => id}, socket) do
    case SourcesAPI.toggle(id) do
      {:ok, _} ->
        {:noreply, assign_sources(socket)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, format_update_error(reason))}
    end
  end

  def handle_event("duplicate", %{"id" => id}, socket) do
    case SourcesAPI.duplicate(id) do
      {:ok, source} ->
        {:noreply, push_navigate(socket, to: "/sources/#{source.id}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, format_update_error(reason))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    case SourcesAPI.delete(id) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Source deleted.") |> assign_sources()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, format_update_error(reason))}
    end
  end

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div class="page-header">
      <h1>Sources</h1>
      <a href="/sources/new" class="btn btn-primary">Add Source</a>
    </div>

    <table class="table" id="sources-table" data-relays={avatar_relays()} phx-hook="SourceAvatars">
      <thead>
        <tr>
          <th>Name</th>
          <th>URL</th>
          <th>Type</th>
          <th>Mode</th>
          <th>Relays</th>
          <th>Status</th>
          <th>Actions</th>
        </tr>
      </thead>
      <tbody>
        <%= if @sources == [] do %>
          <tr>
            <td colspan="7" class="empty-state">
              No sources configured. <a href="/sources/new">Add one</a>.
            </td>
          </tr>
        <% else %>
          <tr :for={source <- @sources} id={"source-#{source.id}"}>
            <td><.source_author source={source} /></td>
            <td><code class="url">{truncate(source.url, 50)}</code></td>
            <td>{source.type}</td>
            <td>
              <span class={"badge #{if source.mode == "automated", do: "badge-processed", else: "badge-test"}"}>
                {if source.mode == "automated", do: "Automated", else: "Setup"}
              </span>
            </td>
            <td>
              <span class={"badge #{relay_badge_class(target_for(source))}"}>
                {relay_target_label(target_for(source))}
              </span>
            </td>
            <td>
              <span class={"badge #{if source.active, do: "badge-active", else: "badge-inactive"}"}>
                {if source.active, do: "Active", else: "Inactive"}
              </span>
            </td>
            <td class="actions">
              <a href={"/sources/#{source.id}"} class="btn btn-small">Open</a>
              <button
                type="button"
                class="btn btn-small"
                phx-click="duplicate"
                phx-value-id={source.id}
              >
                Duplicate
              </button>
              <button type="button" class="btn btn-small" phx-click="toggle" phx-value-id={source.id}>
                {if source.active, do: "Disable", else: "Enable"}
              </button>
              <button
                type="button"
                class="btn btn-small btn-danger"
                phx-click="delete"
                phx-value-id={source.id}
                data-confirm="Delete this source and all of its articles?"
              >
                Delete
              </button>
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
    """
  end

  @spec assign_sources(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp assign_sources(socket) do
    assign(socket, :sources, Sources.list_sources())
  end
end
