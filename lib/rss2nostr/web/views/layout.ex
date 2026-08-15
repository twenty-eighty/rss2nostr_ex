defmodule Rss2Nostr.Web.Views.Layout do
  @moduledoc """
  Base layout for all HTML pages.
  """

  def render(title, content, opts \\ []) do
    active_nav = Keyword.get(opts, :active_nav, "")
    wide? = Keyword.get(opts, :wide, false)
    npub = Rss2Nostr.Web.Auth.current_npub()
    npub_short = shorten_npub(npub)
    container_class = if wide?, do: "container container-wide", else: "container"

    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>#{title} - RSS2Nostr</title>
      <link rel="stylesheet" href="/static/style.css">
    </head>
    <body>
      <nav class="navbar">
        <div class="nav-brand">
          <a href="/">RSS2Nostr</a>
        </div>
        <ul class="nav-links">
          <li><a href="/" class="#{if active_nav == "dashboard", do: "active"}">Dashboard</a></li>
          <li><a href="/sources" class="#{if active_nav == "sources", do: "active"}">Sources</a></li>
          <li><a href="/posts" class="#{if active_nav == "posts", do: "active"}">Posts</a></li>
          <li><a href="/scheduler" class="#{if active_nav == "scheduler", do: "active"}">Scheduler</a></li>
          <li><a href="/settings" class="#{if active_nav == "settings", do: "active"}">Settings</a></li>
          <li class="nav-session">
            #{if npub_short, do: "<span class=\"nav-npub\" title=\"#{escape_html(npub)}\">#{escape_html(npub_short)}</span>"}
            <form action="/logout" method="post" class="nav-logout">
              <button type="submit" class="btn btn-small btn-secondary">Logout</button>
            </form>
          </li>
        </ul>
      </nav>
      <main class="#{container_class}">
        #{content}
      </main>
      <footer class="footer">
        <p>RSS2Nostr v0.1.0</p>
      </footer>
    </body>
    </html>
    """
  end

  defp shorten_npub(nil), do: nil

  defp shorten_npub(npub) when is_binary(npub) and byte_size(npub) > 16 do
    String.slice(npub, 0, 8) <> "…" <> String.slice(npub, -8, 8)
  end

  defp shorten_npub(npub), do: npub

  defp escape_html(nil), do: ""

  defp escape_html(str) when is_binary(str) do
    str
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end
end
