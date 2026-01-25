defmodule Rss2Nostr.Web.Views.Error do
  @moduledoc """
  Error page views.
  """

  alias Rss2Nostr.Web.Views.Layout

  def not_found do
    content = """
    <div class="error-page">
      <h1>404 - Page Not Found</h1>
      <p>The page you're looking for doesn't exist.</p>
      <p><a href="/" class="btn btn-primary">Go to Dashboard</a></p>
    </div>
    """

    Layout.render("Not Found", content)
  end

  def bad_request(message \\ nil) do
    content = """
    <div class="error-page">
      <h1>400 - Bad Request</h1>
      <p>The request could not be understood.</p>
      #{if message, do: "<p><code>#{message}</code></p>"}
      <p><a href="/" class="btn btn-primary">Go to Dashboard</a></p>
    </div>
    """

    Layout.render("Bad Request", content)
  end

  def server_error(message \\ nil) do
    content = """
    <div class="error-page">
      <h1>500 - Server Error</h1>
      <p>Something went wrong.</p>
      #{if message, do: "<p><code>#{message}</code></p>"}
      <p><a href="/" class="btn btn-primary">Go to Dashboard</a></p>
    </div>
    """

    Layout.render("Error", content)
  end
end
