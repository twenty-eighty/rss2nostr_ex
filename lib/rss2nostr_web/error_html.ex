defmodule Rss2NostrWeb.ErrorHTML do
  @moduledoc false

  def render(template, assigns) do
    case template do
      "404.html" ->
        error_page(assigns, "404 - Page Not Found", "The page you're looking for doesn't exist.")

      "400.html" ->
        error_page(assigns, "400 - Bad Request", "The request could not be understood.")

      "500.html" ->
        error_page(assigns, "500 - Server Error", "Something went wrong.")

      other ->
        Phoenix.Controller.status_message_from_template(other)
    end
  end

  defp error_page(_assigns, heading, message) do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>#{heading} - RSS2Nostr</title>
      <link rel="stylesheet" href="/static/style.css">
    </head>
    <body>
      <main class="container">
        <div class="error-page">
          <h1>#{heading}</h1>
          <p>#{message}</p>
          <p><a href="/" class="btn btn-primary">Go to Dashboard</a></p>
        </div>
      </main>
    </body>
    </html>
    """
  end
end
