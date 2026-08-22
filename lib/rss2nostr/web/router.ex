defmodule Rss2Nostr.Web.Router do
  @moduledoc """
  Web router for the RSS2Nostr admin interface.
  """

  use Plug.Router

  alias Rss2Nostr.Web.{Auth, CodeReloader, Views, API}

  @parsers Plug.Parsers.init(
             parsers: [:urlencoded, :json],
             pass: ["*/*"],
             json_decoder: Jason
           )

  plug(:reload_code)
  plug(Plug.Logger)
  plug(:match)
  plug(:maybe_parse)
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

  forward("/mcp",
    to: ExMCP.HttpPlug,
    init_opts: [
      handler: Rss2Nostr.MCP.Server,
      protocol_mode: :prefer_modern,
      server_info: %{name: "rss2nostr", version: "0.1.0"},
      handler_call_timeout: 60_000,
      cors_enabled: true,
      allowed_origins: :any,
      allowed_hosts: :any
    ]
  )

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
        {message, kind} = publish_notice(result)

        redirect(
          conn,
          with_flash("/sources/#{id}?tab=articles", message, kind)
        )

      {:error, :not_found} ->
        send_html(conn, 404, Views.Error.not_found())

      {:error, :invalid_id} ->
        send_html(conn, 400, Views.Error.bad_request())

      {:error, reason} ->
        redirect(
          conn,
          with_flash("/sources/#{id}?tab=articles", to_string(reason), "error")
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
        notice: conn.query_params["notice"],
        notice_kind: conn.query_params["notice_kind"]
      )

    send_html(conn, 200, html)
  end

  post "/posts/publish-selected" do
    dest = return_to(conn, "/posts")

    case API.Posts.publish_selected(conn.body_params) do
      {:ok, result} ->
        {message, kind} = publish_notice(result)
        redirect(conn, with_flash(dest, message, kind))

      {:error, reason} ->
        redirect(conn, with_flash(dest, to_string(reason), "error"))
    end
  end

  get "/posts/:id" do
    case API.Posts.get(id) do
      {:ok, _post} ->
        html =
          Views.Posts.show(id,
            notice: conn.query_params["notice"],
            notice_kind: conn.query_params["notice_kind"],
            return_to: conn.query_params["return_to"]
          )

        send_html(conn, 200, html)

      {:error, :not_found} ->
        send_html(conn, 404, Views.Error.not_found())

      {:error, :invalid_id} ->
        send_html(conn, 400, Views.Error.bad_request())
    end
  end

  post "/posts/:id/process" do
    case API.Posts.process(id) do
      {:ok, post} ->
        if wants_json?(conn) do
          send_json(conn, 200, process_result(post))
        else
          redirect(conn, return_to(conn, "/posts/#{id}"))
        end

      {:error, :not_found} ->
        if wants_json?(conn) do
          send_json(conn, 404, %{error: "Post not found"})
        else
          send_html(conn, 404, Views.Error.not_found())
        end

      {:error, :invalid_id} ->
        if wants_json?(conn) do
          send_json(conn, 400, %{error: "Invalid post id"})
        else
          send_html(conn, 400, Views.Error.bad_request())
        end
    end
  end

  post "/posts/:id/publish" do
    dest = return_to(conn, "/posts/#{id}")

    case API.Posts.publish(id, conn.body_params) do
      {:ok, result} ->
        {message, kind} = publish_result_notice(result)
        redirect(conn, with_flash(dest, message, kind))

      {:error, :not_found} ->
        send_html(conn, 404, Views.Error.not_found())

      {:error, :invalid_id} ->
        send_html(conn, 400, Views.Error.bad_request())

      {:error, reason} ->
        redirect(conn, with_flash(dest, format_error(reason), "error"))
    end
  end

  post "/posts/:id/revise" do
    case API.Posts.revise(id) do
      {:ok, _post} ->
        redirect(
          conn,
          "/posts/#{id}?notice=#{URI.encode_www_form("Reconverted from HTML and moved to staging")}"
        )

      {:error, :not_found} ->
        send_html(conn, 404, Views.Error.not_found())

      {:error, :invalid_id} ->
        send_html(conn, 400, Views.Error.bad_request())

      {:error, reason} ->
        redirect(conn, "/posts/#{id}?notice=#{URI.encode_www_form(to_string(reason))}")
    end
  end

  post "/posts/:id" do
    case API.Posts.update(id, conn.body_params) do
      {:ok, _post} ->
        redirect(conn, post_show_path(conn, id, "Saved"))

      {:error, :not_found} ->
        send_html(conn, 404, Views.Error.not_found())

      {:error, :invalid_id} ->
        send_html(conn, 400, Views.Error.bad_request())

      {:error, reason} ->
        redirect(conn, post_show_path(conn, id, format_update_error(reason), "error"))
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

  defp wants_json?(conn) do
    conn
    |> get_req_header("accept")
    |> Enum.any?(&String.contains?(&1, "application/json"))
  end

  defp process_result(post) do
    %{
      id: post.id,
      status: post.status,
      status_name: Rss2Nostr.Posts.Post.status_name(post.status),
      status_label: Rss2Nostr.Posts.Post.status_label(post.status),
      last_error: post.last_error,
      selectable: post.status == Rss2Nostr.Posts.Post.status_processed()
    }
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

  defp return_to(conn, fallback) do
    case conn.body_params["return_to"] do
      "//" <> _ -> fallback
      "/" <> _ = path -> path
      _ -> fallback
    end
  end

  defp maybe_parse(conn, _opts) do
    if mcp_path?(conn), do: conn, else: Plug.Parsers.call(conn, @parsers)
  end

  defp mcp_path?(%Plug.Conn{path_info: ["mcp" | _]}), do: true
  defp mcp_path?(_), do: false

  defp setup_session(conn, _opts) do
    cond do
      mcp_path?(conn) ->
        conn

      conn.private[:plug_session_fetch] == :done ->
        conn

      true ->
        conn
        |> Map.put(:secret_key_base, Auth.secret_key_base())
        |> Plug.Session.call(Plug.Session.init(Auth.session_opts()))
        |> fetch_session()
    end
  end

  defp require_admin(conn, _opts) do
    cond do
      mcp_path?(conn) ->
        Rss2Nostr.MCP.Auth.call(conn)

      Auth.public_path?(conn) ->
        conn

      Auth.logged_in?(conn) ->
        Auth.put_current_pubkey(Auth.session_pubkey(conn))
        conn

      api_path?(conn) ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          401,
          Jason.encode!(%{error: "Session expired. Reload the page and sign in."})
        )
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
      notice: conn.query_params["notice"],
      notice_kind: conn.query_params["notice_kind"]
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
    base = "Published #{result.published}. Failed #{result.failed}."

    message =
      case result[:errors] do
        [] -> base
        nil -> base
        issues -> base <> " " <> Enum.join(issues, " ")
      end

    kind =
      cond do
        result.failed > 0 -> "error"
        issues?(result) -> "warning"
        true -> "success"
      end

    {message, kind}
  end

  defp publish_result_notice(%{failed_relays: [_ | _], report: report}) when is_binary(report) do
    {"Published, with issues. #{report}", "warning"}
  end

  defp publish_result_notice(%{report: report}) when is_binary(report) and report != "" do
    {report, "success"}
  end

  defp publish_result_notice(_), do: {"Published.", "success"}

  defp issues?(%{errors: [_ | _]}), do: true
  defp issues?(_), do: false

  defp with_flash(path, message, kind) do
    sep = if String.contains?(path, "?"), do: "&", else: "?"
    path <> sep <> URI.encode_query(%{"notice" => message, "notice_kind" => kind})
  end

  defp post_show_path(conn, id, notice, kind \\ "success") do
    path = with_flash("/posts/#{id}", notice, kind)

    case conn.body_params["return_to"] do
      "//" <> _ -> path
      "/" <> _ = from -> path <> "&return_to=" <> URI.encode_www_form(from)
      _ -> path
    end
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: Rss2Nostr.Nostr.Relay.format_error(reason)

  defp reprocess_notice(result) do
    "Reprocessed #{result.processed}. Failed #{result.errors}."
  end

  defp format_update_error(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
    |> Enum.map_join("; ", fn {field, msgs} -> "#{field}: #{Enum.join(msgs, ", ")}" end)
  end

  defp format_update_error(reason), do: to_string(reason)

  defp parse_page(nil), do: 1

  defp parse_page(value) when is_binary(value) do
    case Integer.parse(value) do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end

  defp parse_page(_), do: 1
end
