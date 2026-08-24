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

  get "/auth/challenge" do
    conn = rate_limit_auth!(conn)

    if conn.halted do
      conn
    else
      {conn, payload} = Auth.new_challenge(conn)
      send_json(conn, 200, payload)
    end
  end

  post "/auth/login" do
    conn = rate_limit_auth!(conn)

    if conn.halted do
      conn
    else
      event = conn.body_params["event"] || conn.body_params[:event]

      case Auth.login(conn, event) do
        {:ok, conn} ->
          send_json(conn, 200, %{ok: true})

        {:error, conn, reason} ->
          send_json(conn, 401, %{error: login_error_message(reason)})
      end
    end
  end

  post "/logout" do
    conn
    |> Auth.logout()
    |> redirect("/login")
  end

  get "/health" do
    send_resp(conn, 200, "ok")
  end

  forward("/mcp", to: Rss2Nostr.MCP.Http)

  # ============================================================================
  # Sources
  # ============================================================================

  post "/sources" do
    case API.Sources.create(conn.body_params) do
      {:ok, source} ->
        redirect(conn, "/sources/#{source.id}")

      {:error, changeset} ->
        redirect(conn, with_flash("/sources/new", format_update_error(changeset), "error"))
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
            redirect(
              conn,
              with_flash(
                "/sources/#{source.id}?tab=#{tab}",
                format_update_error(changeset),
                "error"
              )
            )
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

  post "/posts/reprocess-selected" do
    dest = return_to(conn, "/posts")
    {:ok, result} = API.Posts.reprocess_selected(conn.body_params)
    redirect(conn, with_flash(dest, reprocess_notice(result), "success"))
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

  post "/posts/:id/reprocess" do
    case API.Posts.reprocess(id) do
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

  @spec send_html(Plug.Conn.t(), non_neg_integer(), iodata()) :: Plug.Conn.t()
  defp send_html(conn, status, html) do
    conn
    |> put_resp_content_type("text/html")
    |> maybe_disable_cache()
    |> send_resp(status, html)
  end

  @spec reload_code(Plug.Conn.t(), Plug.opts()) :: Plug.Conn.t()
  defp reload_code(conn, _opts), do: CodeReloader.plug(conn, [])

  @spec maybe_disable_cache(Plug.Conn.t()) :: Plug.Conn.t()
  defp maybe_disable_cache(conn) do
    if CodeReloader.enabled?() do
      put_resp_header(conn, "cache-control", "no-store")
    else
      conn
    end
  end

  @spec wants_json?(Plug.Conn.t()) :: boolean()
  defp wants_json?(conn) do
    conn
    |> get_req_header("accept")
    |> Enum.any?(&String.contains?(&1, "application/json"))
  end

  @spec process_result(Rss2Nostr.Posts.Post.t()) :: map()
  defp process_result(post) do
    %{
      id: post.id,
      status: post.status,
      status_name: Rss2Nostr.Posts.Post.status_name(post.status),
      status_label: Rss2Nostr.Posts.Post.status_label(post.status),
      last_error: post.last_error,
      selectable:
        post.status in [
          Rss2Nostr.Posts.Post.status_processed(),
          Rss2Nostr.Posts.Post.status_pending_images()
        ],
      publishable: post.status == Rss2Nostr.Posts.Post.status_processed()
    }
  end

  @spec send_json(Plug.Conn.t(), non_neg_integer(), term()) :: Plug.Conn.t()
  defp send_json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end

  @spec redirect(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  defp redirect(conn, path) do
    conn
    |> put_resp_header("location", path)
    |> send_resp(302, "")
  end

  @spec return_to(Plug.Conn.t(), String.t()) :: String.t()
  defp return_to(conn, fallback) do
    case conn.body_params["return_to"] do
      "//" <> _ -> fallback
      "/" <> _ = path -> path
      _ -> fallback
    end
  end

  @spec maybe_parse(Plug.Conn.t(), Plug.opts()) :: Plug.Conn.t()
  defp maybe_parse(conn, _opts) do
    if mcp_path?(conn), do: conn, else: Plug.Parsers.call(conn, @parsers)
  end

  @spec mcp_path?(Plug.Conn.t()) :: boolean()
  defp mcp_path?(%Plug.Conn{path_info: ["mcp" | _]}), do: true
  defp mcp_path?(_), do: false

  @spec setup_session(Plug.Conn.t(), Plug.opts()) :: Plug.Conn.t()
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

  @spec require_admin(Plug.Conn.t(), Plug.opts()) :: Plug.Conn.t()
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

  @spec api_path?(Plug.Conn.t()) :: boolean()
  defp api_path?(%Plug.Conn{path_info: ["api" | _]}), do: true
  defp api_path?(_), do: false

  @spec login_redirect_path(Plug.Conn.t()) :: String.t()
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

  @spec login_error_message(atom()) :: String.t()
  defp login_error_message(:unauthorized_pubkey), do: "This Nostr key is not an admin."
  defp login_error_message(:missing_challenge), do: "Login challenge missing or already used."
  defp login_error_message(:challenge_expired), do: "Login challenge expired. Try again."
  defp login_error_message(:challenge_mismatch), do: "Login challenge did not match."
  defp login_error_message(:invalid_signature), do: "Invalid event signature."
  defp login_error_message(:invalid_id), do: "Invalid event id."
  defp login_error_message(reason), do: "Login failed (#{reason})."

  @spec rate_limit_auth!(Plug.Conn.t()) :: Plug.Conn.t()
  defp rate_limit_auth!(conn) do
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()

    if Rss2Nostr.Web.RateLimit.allow?({:auth, ip}, 30, 60_000) do
      conn
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(429, Jason.encode!(%{error: "Too many login attempts. Try again later."}))
      |> halt()
    end
  end

  @spec import_notice(map()) :: String.t()
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

  @spec publish_notice(map()) :: {String.t(), String.t()}
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

  @spec publish_result_notice(map()) :: {String.t(), String.t()}
  defp publish_result_notice(%{failed_relays: [_ | _], report: report}) when is_binary(report) do
    {"Published, with issues. #{report}", "warning"}
  end

  defp publish_result_notice(%{report: report}) when is_binary(report) and report != "" do
    {report, "success"}
  end

  defp publish_result_notice(_), do: {"Published.", "success"}

  @spec issues?(map()) :: boolean()
  defp issues?(%{errors: [_ | _]}), do: true
  defp issues?(_), do: false

  @spec with_flash(String.t(), String.t(), String.t()) :: String.t()
  defp with_flash(path, message, kind) do
    sep = if String.contains?(path, "?"), do: "&", else: "?"
    path <> sep <> URI.encode_query(%{"notice" => message, "notice_kind" => kind})
  end

  @spec post_show_path(Plug.Conn.t(), term(), String.t(), String.t()) :: String.t()
  defp post_show_path(conn, id, notice, kind \\ "success") do
    path = with_flash("/posts/#{id}", notice, kind)

    case conn.body_params["return_to"] do
      "//" <> _ -> path
      "/" <> _ = from -> path <> "&return_to=" <> URI.encode_www_form(from)
      _ -> path
    end
  end

  @spec format_error(term()) :: String.t()
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: Rss2Nostr.Nostr.Relay.format_error(reason)

  @spec reprocess_notice(map()) :: String.t()
  defp reprocess_notice(result) do
    "Reprocessed #{result.processed}. Failed #{result.errors}."
  end

  @spec format_update_error(Ecto.Changeset.t() | term()) :: String.t()
  defp format_update_error(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
    |> Enum.map_join("; ", fn {field, msgs} -> "#{field}: #{Enum.join(msgs, ", ")}" end)
  end

  defp format_update_error(reason), do: to_string(reason)
end
