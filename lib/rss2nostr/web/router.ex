defmodule Rss2Nostr.Web.Router do
  @moduledoc """
  Web router for the RSS2Nostr admin interface.
  """

  use Plug.Router

  alias Rss2Nostr.Web.{Auth, CodeReloader, Views, API}

  plug(:reload_code)
  plug(Plug.Logger)
  plug(:match)

  plug(Plug.Parsers,
    parsers: [:urlencoded, :json],
    pass: ["*/*"],
    json_decoder: Jason
  )

  plug(:setup_session)
  plug(:require_admin)
  plug(:dispatch)

  # ============================================================================
  # Auth (NIP-07)
  # ============================================================================

  get "/login" do
    if Auth.logged_in?(conn) do
      redirect(conn, "/")
    else
      html = Views.Login.render()
      send_html(conn, 200, html)
    end
  end

  get "/auth/challenge" do
    {conn, payload} = Auth.new_challenge(conn)
    send_json(conn, 200, payload)
  end

  post "/auth/login" do
    event = conn.body_params["event"] || conn.body_params[:event]

    case Auth.login(conn, event) do
      {:ok, conn} ->
        send_json(conn, 200, %{ok: true})

      {:error, conn, reason} ->
        send_json(conn, 401, %{error: login_error_message(reason)})
    end
  end

  post "/logout" do
    conn
    |> Auth.logout()
    |> redirect("/login")
  end

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
      {:ok, source} ->
        redirect(conn, "/sources/#{source.id}")

      {:error, changeset} ->
        html = Views.Sources.new(errors: changeset_errors(changeset), params: conn.body_params)
        send_html(conn, 422, html)
    end
  end

  get "/sources/:id" do
    case API.Sources.get(id) do
      {:ok, source} ->
        html = Views.Sources.show(source, source_view_opts(conn))
        send_html(conn, 200, html)

      {:error, :not_found} ->
        send_html(conn, 404, Views.Error.not_found())

      {:error, :invalid_id} ->
        send_html(conn, 400, Views.Error.bad_request())
    end
  end

  post "/sources/:id" do
    tab = conn.body_params["tab"] || "compose"

    case API.Sources.get(id) do
      {:ok, source} ->
        case API.Sources.update(source, conn.body_params) do
          {:ok, updated} ->
            redirect(conn, "/sources/#{updated.id}?tab=#{tab}&saved=1")

          {:error, changeset} ->
            html =
              Views.Sources.show(source,
                tab: tab,
                errors: changeset_errors(changeset),
                params: conn.body_params
              )

            send_html(conn, 422, html)
        end

      {:error, :not_found} ->
        send_html(conn, 404, Views.Error.not_found())

      {:error, :invalid_id} ->
        send_html(conn, 400, Views.Error.bad_request())
    end
  end

  post "/sources/:id/import" do
    case API.Sources.import_now(id) do
      {:ok, result} ->
        redirect(
          conn,
          "/sources/#{id}?tab=articles&notice=#{URI.encode_www_form(import_notice(result))}"
        )

      {:error, :not_found} ->
        send_html(conn, 404, Views.Error.not_found())

      {:error, :invalid_id} ->
        send_html(conn, 400, Views.Error.bad_request())
    end
  end

  post "/sources/:id/publish-selected" do
    case API.Sources.publish_selected(id, conn.body_params) do
      {:ok, result} ->
        redirect(
          conn,
          "/sources/#{id}?tab=articles&notice=#{URI.encode_www_form(publish_notice(result))}"
        )

      {:error, :not_found} ->
        send_html(conn, 404, Views.Error.not_found())

      {:error, :invalid_id} ->
        send_html(conn, 400, Views.Error.bad_request())

      {:error, reason} ->
        redirect(
          conn,
          "/sources/#{id}?tab=articles&notice=#{URI.encode_www_form(to_string(reason))}"
        )
    end
  end

  post "/sources/:id/reprocess-selected" do
    case API.Sources.reprocess_selected(id, conn.body_params) do
      {:ok, result} ->
        redirect(
          conn,
          "/sources/#{id}?tab=articles&notice=#{URI.encode_www_form(reprocess_notice(result))}"
        )

      {:error, :not_found} ->
        send_html(conn, 404, Views.Error.not_found())

      {:error, :invalid_id} ->
        send_html(conn, 400, Views.Error.bad_request())
    end
  end

  post "/sources/:id/duplicate" do
    case API.Sources.duplicate(id, conn.body_params) do
      {:ok, source} ->
        redirect(
          conn,
          "/sources/#{source.id}?tab=feed&notice=#{URI.encode_www_form("Duplicated. Change the feed URL if this copy should follow a different RSS or Atom feed.")}"
        )

      {:error, :not_found} ->
        send_html(conn, 404, Views.Error.not_found())

      {:error, :invalid_id} ->
        send_html(conn, 400, Views.Error.bad_request())

      {:error, _reason} ->
        redirect(conn, "/sources/#{id}")
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
    end
  end

  # ============================================================================
  # Posts
  # ============================================================================

  get "/posts" do
    status = conn.query_params["status"]
    source_id = conn.query_params["source_id"]
    q = conn.query_params["q"]
    page = parse_page(conn.query_params["page"])

    html =
      Views.Posts.index(
        status: status,
        source_id: source_id,
        q: q,
        page: page,
        notice: conn.query_params["notice"]
      )
    send_html(conn, 200, html)
  end

  post "/posts/publish-selected" do
    case API.Posts.publish_selected(conn.body_params) do
      {:ok, result} ->
        redirect(conn, "/posts?notice=#{URI.encode_www_form(publish_notice(result))}")

      {:error, reason} ->
        redirect(conn, "/posts?notice=#{URI.encode_www_form(to_string(reason))}")
    end
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
    end
  end

  post "/posts/:id/publish" do
    case API.Posts.publish(id, conn.body_params) do
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

  post "/api/sources/discover" do
    case API.Sources.discover(conn.body_params) do
      {:ok, result} -> send_json(conn, 200, result)
      {:error, reason} -> send_json(conn, 422, %{error: reason})
    end
  end

  post "/api/sources/preview" do
    case API.Sources.preview(conn.body_params) do
      {:ok, result} -> send_json(conn, 200, result)
      {:error, reason} -> send_json(conn, 422, %{error: reason})
    end
  end

  post "/api/sources/compose-preview" do
    case API.Sources.compose_preview(conn.body_params) do
      {:ok, result} -> send_json(conn, 200, result)
      {:error, reason} -> send_json(conn, 422, %{error: reason})
    end
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
    |> maybe_disable_cache()
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
    |> maybe_disable_cache()
    |> send_resp(status, html)
  end

  defp reload_code(conn, _opts), do: CodeReloader.plug(conn, [])

  defp maybe_disable_cache(conn) do
    if CodeReloader.enabled?() do
      put_resp_header(conn, "cache-control", "no-store")
    else
      conn
    end
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

  defp setup_session(conn, _opts) do
    if conn.private[:plug_session_fetch] == :done do
      conn
    else
      conn
      |> Map.put(:secret_key_base, Auth.secret_key_base())
      |> Plug.Session.call(Plug.Session.init(Auth.session_opts()))
      |> fetch_session()
    end
  end

  defp require_admin(conn, _opts) do
    cond do
      Auth.public_path?(conn) ->
        conn

      Auth.logged_in?(conn) ->
        Auth.put_current_pubkey(Auth.session_pubkey(conn))
        conn

      api_path?(conn) ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{error: "unauthorized"}))
        |> halt()

      true ->
        conn
        |> put_resp_header("location", login_redirect_path(conn))
        |> send_resp(302, "")
        |> halt()
    end
  end

  defp api_path?(%Plug.Conn{path_info: ["api" | _]}), do: true
  defp api_path?(_), do: false

  defp login_redirect_path(%Plug.Conn{method: "GET", request_path: path} = conn)
       when path not in ["", "/login"] do
    query = conn.query_string

    next =
      if query == "" do
        path
      else
        path <> "?" <> query
      end

    "/login?next=" <> URI.encode_www_form(next)
  end

  defp login_redirect_path(_), do: "/login"

  defp login_error_message(:unauthorized_pubkey), do: "This Nostr key is not an admin."
  defp login_error_message(:missing_challenge), do: "Login challenge missing or already used."
  defp login_error_message(:challenge_expired), do: "Login challenge expired. Try again."
  defp login_error_message(:challenge_mismatch), do: "Login challenge did not match."
  defp login_error_message(:invalid_signature), do: "Invalid event signature."
  defp login_error_message(:invalid_id), do: "Invalid event id."
  defp login_error_message(reason), do: "Login failed (#{reason})."

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp source_view_opts(conn) do
    [
      tab: conn.query_params["tab"] || "compose",
      saved: conn.query_params["saved"] == "1",
      notice: conn.query_params["notice"]
    ]
  end

  defp import_notice(result) do
    skipped =
      if result.skipped > 0 do
        " Skipped #{result.skipped} already imported."
      else
        ""
      end

    errors =
      case result.errors do
        [] -> ""
        list -> " Errors: #{Enum.join(list, "; ")}."
      end

    "Imported #{result.imported} articles, processed #{result.processed}.#{skipped}#{errors}"
  end

  defp publish_notice(result) do
    "Published #{result.published}. Failed #{result.failed}."
  end

  defp reprocess_notice(result) do
    "Reprocessed #{result.processed}. Failed #{result.errors}."
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
