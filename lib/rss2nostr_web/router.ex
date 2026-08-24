defmodule Rss2NostrWeb.Router do
  @moduledoc """
  Phoenix router for the admin LiveView UI.

  JSON API, MCP, health, auth challenge/login, and CSS stay on
  `Rss2Nostr.Web.Router`.
  """

  use Rss2NostrWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {Rss2NostrWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :admin do
    plug Rss2NostrWeb.Plugs.RequireAdmin
  end

  scope "/", Rss2NostrWeb do
    pipe_through :browser

    get "/login", SessionController, :new
    post "/logout", SessionController, :delete
  end

  scope "/", Rss2NostrWeb do
    pipe_through [:browser, :admin]

    live_session :admin, on_mount: [{Rss2NostrWeb.AuthHook, :require_admin}] do
      live "/", DashboardLive
      live "/sources", SourceIndexLive
      live "/sources/new", SourceNewLive
      live "/sources/:id", SourceLive
      live "/posts", PostIndexLive
      live "/posts/:id", PostShowLive
      live "/scheduler", SchedulerLive
      live "/settings", SettingsLive
    end
  end

  forward "/", Rss2Nostr.Web.Router
end
