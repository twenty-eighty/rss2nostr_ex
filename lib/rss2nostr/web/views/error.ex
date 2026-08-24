defmodule Rss2Nostr.Web.Views.Error do
  @moduledoc """
  HTML error pages for Plug routes that are not handled by Phoenix.
  """

  def not_found do
    error_page("404 - Page Not Found", "The page you're looking for doesn't exist.")
  end

  def bad_request(message \\ nil) do
    detail = if message, do: "<p><code>#{escape(message)}</code></p>", else: ""
    error_page("400 - Bad Request", "The request could not be understood.", detail)
  end

  def server_error(message \\ nil) do
    detail = if message, do: "<p><code>#{escape(message)}</code></p>", else: ""
    error_page("500 - Server Error", "Something went wrong.", detail)
  end

  defp error_page(heading, message, extra \\ "") do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>#{heading} - RSS2Nostr</title>
      <link rel="icon" href="/favicon.svg" type="image/svg+xml">
      <link rel="icon" href="/favicon.ico" sizes="any">
      <link rel="apple-touch-icon" href="/apple-touch-icon.png">
      <link rel="stylesheet" href="/static/style.css">
    </head>
    <body>
      <main class="container">
        <div class="error-page">
          <h1>#{heading}</h1>
          <p>#{message}</p>
          #{extra}
          <p><a href="/" class="btn btn-primary">Go to Dashboard</a></p>
        </div>
      </main>
    </body>
    </html>
    """
  end

  defp escape(value) do
    value
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end
end
