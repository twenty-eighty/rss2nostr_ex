defmodule Rss2Nostr.Web.Views.Posts do
  @moduledoc """
  Views for post management.
  """

  alias Rss2Nostr.Web.Views.Layout
  alias Rss2Nostr.Posts
  alias Rss2Nostr.Posts.Post

  @per_page 20

  def index(opts \\ []) do
    status_filter = Keyword.get(opts, :status)
    page = Keyword.get(opts, :page, 1)
    offset = (page - 1) * @per_page

    posts =
      case status_filter do
        nil -> Posts.list_recent_posts(limit: @per_page, offset: offset)
        "" -> Posts.list_recent_posts(limit: @per_page, offset: offset)
        status -> Posts.list_posts_by_status(status, limit: @per_page, offset: offset)
      end

    rows =
      if Enum.empty?(posts) do
        "<tr><td colspan=\"5\" class=\"empty-state\">No posts found.</td></tr>"
      else
        Enum.map_join(posts, "", fn post ->
          status_class = status_to_class(post.status)
          status_label = Post.status_label(post.status)

          """
          <tr>
            <td><a href="/posts/#{post.id}">#{escape_html(truncate(post.title, 60))}</a></td>
            <td><span class="badge #{status_class}">#{status_label}</span></td>
            <td>#{escape_html(truncate(post.source_url, 40))}</td>
            <td>#{format_datetime(post.published_at)}</td>
            <td class="actions">
              #{action_buttons(post)}
            </td>
          </tr>
          """
        end)
      end

    content = """
    <div class="page-header">
      <h1>Posts</h1>
    </div>

    <div class="filter-bar">
      <a href="/posts" class="btn btn-small #{if is_nil(status_filter), do: "btn-active"}">All</a>
      <a href="/posts?status=0" class="btn btn-small #{if status_filter == "0", do: "btn-active"}">New</a>
      <a href="/posts?status=2" class="btn btn-small #{if status_filter == "2", do: "btn-active"}">Processed</a>
      <a href="/posts?status=6" class="btn btn-small #{if status_filter == "6", do: "btn-active"}">Published</a>
    </div>

    <table class="table">
      <thead>
        <tr>
          <th>Title</th>
          <th>Status</th>
          <th>Source</th>
          <th>Published</th>
          <th>Actions</th>
        </tr>
      </thead>
      <tbody>
        #{rows}
      </tbody>
    </table>

    <div class="pagination">
      #{if page > 1, do: "<a href=\"/posts?page=#{page - 1}#{if status_filter, do: "&status=#{status_filter}"}\" class=\"btn btn-small\">&larr; Previous</a>"}
      <span>Page #{page}</span>
      #{if length(posts) == @per_page, do: "<a href=\"/posts?page=#{page + 1}#{if status_filter, do: "&status=#{status_filter}"}\" class=\"btn btn-small\">Next &rarr;</a>"}
    </div>
    """

    Layout.render("Posts", content, active_nav: "posts")
  end

  def show(id) do
    case Posts.get_post(String.to_integer(id)) do
      nil ->
        Layout.render(
          "Post Not Found",
          "<h1>Post Not Found</h1><p>The requested post does not exist.</p>",
          active_nav: "posts"
        )

      post ->
        status_class = status_to_class(post.status)
        status_label = Post.status_label(post.status)

        content = """
        <div class="page-header">
          <h1>#{escape_html(post.title)}</h1>
          <span class="badge #{status_class}">#{status_label}</span>
        </div>

        <div class="post-meta">
          #{if post.source_url, do: "<p><strong>Source:</strong> <a href=\"#{escape_html(post.source_url)}\" target=\"_blank\">#{escape_html(truncate(post.source_url, 60))}</a></p>"}
          #{if post.published_at, do: "<p><strong>Published:</strong> #{format_datetime(post.published_at)}</p>"}
          #{if post.event_id, do: "<p><strong>Event ID:</strong> <code>#{post.event_id}</code></p>"}
          #{if post.nostr_address, do: "<p><strong>Nostr Address:</strong> <code>#{truncate(post.nostr_address, 60)}</code></p>"}
        </div>

        <div class="post-actions">
          #{if post.status == Post.status_new() do
          """
          <form action="/posts/#{post.id}/process" method="POST" style="display:inline">
            <button type="submit" class="btn btn-primary">Process</button>
          </form>
          """
        end}
          #{if post.status == Post.status_processed() do
          """
          <form action="/posts/#{post.id}/export" method="POST" style="display:inline">
            <button type="submit" class="btn btn-primary">Export to Nostr</button>
          </form>
          """
        end}
          <a href="/posts" class="btn btn-secondary">Back to List</a>
        </div>

        #{if post.image do
          """
          <div class="post-image">
            <h3>Featured Image</h3>
            <img src="#{escape_html(post.image)}" alt="Featured image" style="max-width: 400px;">
          </div>
          """
        end}

        <div class="post-content">
          <h3>Content</h3>
          <div class="content-preview">
            #{if post.content, do: "<pre>#{escape_html(post.content)}</pre>", else: "<p class=\"empty-state\">No content yet. Process the post first.</p>"}
          </div>
        </div>

        #{if post.source_html do
          """
          <details class="post-source">
            <summary>Original HTML</summary>
            <pre>#{escape_html(truncate(post.source_html, 2000))}</pre>
          </details>
          """
        end}
        """

        Layout.render(post.title, content, active_nav: "posts")
    end
  end

  defp action_buttons(post) do
    case post.status do
      0 ->
        """
        <form action="/posts/#{post.id}/process" method="POST" style="display:inline">
          <button type="submit" class="btn btn-small">Process</button>
        </form>
        """

      2 ->
        """
        <form action="/posts/#{post.id}/export" method="POST" style="display:inline">
          <button type="submit" class="btn btn-small">Export</button>
        </form>
        """

      _ ->
        ""
    end
  end

  defp status_to_class(status) do
    case status do
      0 -> "badge-new"
      1 -> "badge-processing"
      2 -> "badge-processed"
      6 -> "badge-published"
      _ -> "badge-error"
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

  defp format_datetime(nil), do: "-"

  defp format_datetime(dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  end
end
