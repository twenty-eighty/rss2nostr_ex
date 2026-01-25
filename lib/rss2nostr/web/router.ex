defmodule Rss2Nostr.Web.Router do
  @moduledoc """
  Web router for the RSS2Nostr admin interface.
  """

  use Plug.Router
  require Logger

  alias Rss2Nostr.Web.{Views, API}

  plug(Plug.Logger)
  plug(:match)

  plug(Plug.Parsers,
    parsers: [:urlencoded, :json],
    pass: ["*/*"],
    json_decoder: Jason
  )

  plug(:dispatch)

  # ============================================================================
  # Dashboard
  # ============================================================================

  get "/" do
    html = Views.Dashboard.render()
    send_html(conn, 200, html)
  end

  # ============================================================================
  # Sources
  # ============================================================================

  get "/sources" do
    html = Views.Sources.index()
    send_html(conn, 200, html)
  end

  get "/sources/new" do
    html = Views.Sources.new()
    send_html(conn, 200, html)
  end

  post "/sources" do
    case API.Sources.create(conn.body_params) do
      {:ok, _source} ->
        redirect(conn, "/sources")

      {:error, changeset} ->
        html = Views.Sources.new(errors: changeset_errors(changeset))
        send_html(conn, 422, html)
    end
  end

  post "/sources/:id/toggle" do
    case API.Sources.toggle(id) do
      {:ok, _source} -> redirect(conn, "/sources")
      {:error, :not_found} -> send_html(conn, 404, Views.Error.not_found())
      {:error, :invalid_id} -> send_html(conn, 400, Views.Error.bad_request())
      {:error, _reason} -> redirect(conn, "/sources")
    end
  end

  post "/sources/:id/delete" do
    case API.Sources.delete(id) do
      {:ok, _source} -> redirect(conn, "/sources")
      {:error, :not_found} -> send_html(conn, 404, Views.Error.not_found())
      {:error, :invalid_id} -> send_html(conn, 400, Views.Error.bad_request())
      {:error, _reason} -> redirect(conn, "/sources")
    end
  end

  # ============================================================================
  # Posts
  # ============================================================================

  get "/posts" do
    status = conn.query_params["status"]
    page = parse_page(conn.query_params["page"])
    html = Views.Posts.index(status: status, page: page)
    send_html(conn, 200, html)
  end

  get "/posts/:id" do
    case API.Posts.get(id) do
      {:ok, _post} ->
        html = Views.Posts.show(id)
        send_html(conn, 200, html)

      {:error, :not_found} ->
        send_html(conn, 404, Views.Error.not_found())

      {:error, :invalid_id} ->
        send_html(conn, 400, Views.Error.bad_request())
    end
  end

  post "/posts/:id/process" do
    case API.Posts.process(id) do
      {:ok, _post} -> redirect(conn, "/posts/#{id}")
      {:error, :not_found} -> send_html(conn, 404, Views.Error.not_found())
      {:error, :invalid_id} -> send_html(conn, 400, Views.Error.bad_request())
      {:error, _reason} -> redirect(conn, "/posts/#{id}")
    end
  end

  post "/posts/:id/publish" do
    case API.Posts.publish(id) do
      {:ok, _result} -> redirect(conn, "/posts/#{id}")
      {:error, :not_found} -> send_html(conn, 404, Views.Error.not_found())
      {:error, :invalid_id} -> send_html(conn, 400, Views.Error.bad_request())
      {:error, _reason} -> redirect(conn, "/posts/#{id}")
    end
  end

  # ============================================================================
  # Scheduler
  # ============================================================================

  get "/scheduler" do
    html = Views.Scheduler.index()
    send_html(conn, 200, html)
  end

  post "/scheduler/start" do
    API.Scheduler.start()
    redirect(conn, "/scheduler")
  end

  post "/scheduler/stop" do
    API.Scheduler.stop()
    redirect(conn, "/scheduler")
  end

  post "/scheduler/run/:task" do
    API.Scheduler.run_task(task)
    redirect(conn, "/scheduler")
  end

  # ============================================================================
  # Settings
  # ============================================================================

  get "/settings" do
    html = Views.Settings.index()
    send_html(conn, 200, html)
  end

  post "/settings" do
    API.Settings.update(conn.body_params)
    redirect(conn, "/settings")
  end

  # ============================================================================
  # API Endpoints (JSON)
  # ============================================================================

  get "/api/status" do
    status = API.Status.overview()
    send_json(conn, 200, status)
  end

  get "/api/sources" do
    sources = API.Sources.list()
    send_json(conn, 200, %{sources: sources})
  end

  get "/api/posts" do
    posts = API.Posts.list(conn.query_params)
    send_json(conn, 200, %{posts: posts})
  end

  # ============================================================================
  # Static Assets (CSS)
  # ============================================================================

  get "/static/style.css" do
    css = Views.Assets.css()

    conn
    |> put_resp_content_type("text/css")
    |> send_resp(200, css)
  end

  # ============================================================================
  # Catch-all
  # ============================================================================

  match _ do
    send_html(conn, 404, Views.Error.not_found())
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp send_html(conn, status, html) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(status, html)
  end

  defp send_json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end

  defp redirect(conn, path) do
    conn
    |> put_resp_header("location", path)
    |> send_resp(302, "")
  end

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp parse_page(nil), do: 1

  defp parse_page(value) when is_binary(value) do
    case Integer.parse(value) do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end

  defp parse_page(_), do: 1
end
