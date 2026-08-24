defmodule Rss2NostrWeb do
  @moduledoc """
  Phoenix entrypoints for the admin UI LiveView layer.
  """

  def static_paths,
    do: ~w(assets images favicon.ico favicon.svg apple-touch-icon.png)

  def router do
    quote do
      use Phoenix.Router, helpers: false

      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
    end
  end

  def controller do
    quote do
      use Phoenix.Controller,
        formats: [:html],
        layouts: [html: Rss2NostrWeb.Layouts]

      import Plug.Conn

      unquote(html_helpers())
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView, layout: {Rss2NostrWeb.Layouts, :app}

      unquote(html_helpers())
    end
  end

  def live_component do
    quote do
      use Phoenix.LiveComponent

      unquote(html_helpers())
    end
  end

  def html do
    quote do
      use Phoenix.Component

      import Phoenix.Controller,
        only: [get_csrf_token: 0, view_module: 1, view_template: 1]

      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      import Phoenix.HTML
      import Rss2NostrWeb.CoreComponents
      import Rss2NostrWeb.LiveHelpers

      alias Phoenix.LiveView.JS

      use Phoenix.VerifiedRoutes,
        endpoint: Rss2NostrWeb.Endpoint,
        router: Rss2NostrWeb.Router,
        statics: Rss2NostrWeb.static_paths()
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
