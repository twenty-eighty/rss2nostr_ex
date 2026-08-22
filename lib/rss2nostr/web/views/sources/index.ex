defmodule Rss2Nostr.Web.Views.Sources.Index do
  @moduledoc false

  alias Rss2Nostr.Nostr.Relays
  alias Rss2Nostr.Sources
  alias Rss2Nostr.Web.Views.{Layout, Sources.Helpers, Sources.Scripts}

  def index do
    sources = Sources.list_sources()

    rows =
      if Enum.empty?(sources) do
        """
        <tr>
          <td colspan="7" class="empty-state">No sources configured. <a href="/sources/new">Add one</a>.</td>
        </tr>
        """
      else
        Enum.map_join(sources, "", fn source ->
          """
          <tr>
            <td>#{Helpers.source_name_cell(source)}</td>
            <td><code class="url">#{Helpers.escape_html(Helpers.truncate(source.url, 50))}</code></td>
            <td>#{source.type}</td>
            <td>
              <span class="badge #{if source.mode == "automated", do: "badge-processed", else: "badge-test"}">
                #{if source.mode == "automated", do: "Automated", else: "Setup"}
              </span>
            </td>
            <td>
              <span class="badge #{Helpers.relay_badge_class(Relays.target_for(source))}">
                #{Helpers.relay_target_label(Relays.target_for(source))}
              </span>
            </td>
            <td>
              <span class="badge #{if source.active, do: "badge-active", else: "badge-inactive"}">
                #{if source.active, do: "Active", else: "Inactive"}
              </span>
            </td>
            <td class="actions">
              <a href="/sources/#{source.id}" class="btn btn-small">Open</a>
              <form action="/sources/#{source.id}/duplicate" method="POST" style="display:inline">
                <button type="submit" class="btn btn-small">Duplicate</button>
              </form>
              <form action="/sources/#{source.id}/toggle" method="POST" style="display:inline">
                <button type="submit" class="btn btn-small">
                  #{if source.active, do: "Disable", else: "Enable"}
                </button>
              </form>
              <form action="/sources/#{source.id}/delete" method="POST" style="display:inline"
                    onsubmit="return confirm('Delete this source and all of its articles?')">
                <button type="submit" class="btn btn-small btn-danger">Delete</button>
              </form>
            </td>
          </tr>
          """
        end)
      end

    content = """
    <div class="page-header">
      <h1>Sources</h1>
      <a href="/sources/new" class="btn btn-primary">Add Source</a>
    </div>

    <table class="table" id="sources-table" data-relays="#{Helpers.escape_attr(Helpers.avatar_relays())}">
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
        #{rows}
      </tbody>
    </table>
    #{Scripts.source_avatar_script()}
    """

    Layout.render("Sources", content, active_nav: "sources")
  end
end

