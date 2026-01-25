defmodule Rss2Nostr.Web.Views.Sources do
  @moduledoc """
  Views for source management.
  """

  alias Rss2Nostr.Web.Views.Layout
  alias Rss2Nostr.Sources

  def index do
    sources = Sources.list_sources()

    rows =
      if Enum.empty?(sources) do
        """
        <tr>
          <td colspan="5" class="empty-state">No sources configured. <a href="/sources/new">Add one</a>.</td>
        </tr>
        """
      else
        Enum.map_join(sources, "", fn source ->
          """
          <tr>
            <td>#{escape_html(source.name)}</td>
            <td><code class="url">#{escape_html(truncate(source.url, 50))}</code></td>
            <td>#{source.type}</td>
            <td>
              <span class="badge #{if source.active, do: "badge-active", else: "badge-inactive"}">
                #{if source.active, do: "Active", else: "Inactive"}
              </span>
            </td>
            <td class="actions">
              <form action="/sources/#{source.id}/toggle" method="POST" style="display:inline">
                <button type="submit" class="btn btn-small">
                  #{if source.active, do: "Disable", else: "Enable"}
                </button>
              </form>
              <form action="/sources/#{source.id}/delete" method="POST" style="display:inline"
                    onsubmit="return confirm('Delete this source?')">
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

    <table class="table">
      <thead>
        <tr>
          <th>Name</th>
          <th>URL</th>
          <th>Type</th>
          <th>Status</th>
          <th>Actions</th>
        </tr>
      </thead>
      <tbody>
        #{rows}
      </tbody>
    </table>
    """

    Layout.render("Sources", content, active_nav: "sources")
  end

  def new(opts \\ []) do
    errors = Keyword.get(opts, :errors, %{})

    content = """
    <h1>Add Source</h1>

    <form action="/sources" method="POST" class="form">
      <div class="form-group">
        <label for="name">Name</label>
        <input type="text" id="name" name="name" required placeholder="e.g., Heise News">
        #{error_message(errors, :name)}
      </div>

      <div class="form-group">
        <label for="url">Feed URL</label>
        <input type="url" id="url" name="url" required placeholder="https://example.com/feed.xml">
        #{error_message(errors, :url)}
      </div>

      <div class="form-group">
        <label for="type">Feed Type</label>
        <select id="type" name="type">
          <option value="atom">Atom</option>
          <option value="rss">RSS</option>
        </select>
      </div>

      <div class="form-group">
        <label for="language">Language</label>
        <input type="text" id="language" name="language" value="de" placeholder="de, en, etc.">
      </div>

      <div class="form-actions">
        <button type="submit" class="btn btn-primary">Add Source</button>
        <a href="/sources" class="btn btn-secondary">Cancel</a>
      </div>
    </form>
    """

    Layout.render("Add Source", content, active_nav: "sources")
  end

  defp error_message(errors, field) do
    case errors[field] do
      nil -> ""
      msgs when is_list(msgs) -> "<span class=\"error\">#{Enum.join(msgs, ", ")}</span>"
      msg -> "<span class=\"error\">#{msg}</span>"
    end
  end

  defp escape_html(str) when is_binary(str) do
    str
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp escape_html(nil), do: ""

  defp truncate(str, max) when is_binary(str) do
    if String.length(str) > max do
      String.slice(str, 0, max) <> "..."
    else
      str
    end
  end

  defp truncate(nil, _max), do: ""
end
