defmodule Rss2Nostr.Web.Views.Layout do
  @moduledoc """
  Base layout for all HTML pages.
  """

  def render(title, content, opts \\ []) do
    active_nav = Keyword.get(opts, :active_nav, "")

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
        </ul>
      </nav>
      <main class="container">
        #{content}
      </main>
      <footer class="footer">
        <p>RSS2Nostr v0.1.0</p>
      </footer>
    </body>
    </html>
    """
  end
end
