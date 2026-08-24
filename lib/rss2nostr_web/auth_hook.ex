defmodule Rss2NostrWeb.AuthHook do
  @moduledoc false

  import Phoenix.LiveView
  import Phoenix.Component

  alias Rss2Nostr.Web.Auth

  @spec on_mount(atom(), map(), map(), Phoenix.LiveView.Socket.t()) :: {:cont, Phoenix.LiveView.Socket.t()} | {:halt, Phoenix.LiveView.Socket.t()}
  def on_mount(:require_admin, _params, session, socket) do
    pubkey = session_pubkey(session)

    if is_binary(pubkey) and Auth.allowed?(pubkey) do
      Auth.put_current_pubkey(pubkey)

      {:cont,
       socket
       |> assign(:current_pubkey, pubkey)
       |> assign(:current_npub, Auth.current_npub())
       |> assign(:wide, false)
       |> assign(:active_nav, "")}
    else
      {:halt, redirect(socket, to: "/login?next=#{URI.encode_www_form(requested_path(socket))}")}
    end
  end

  @spec session_pubkey(map()) :: String.t() | nil
  defp session_pubkey(session) when is_map(session) do
    session["admin_pubkey"] || session[:admin_pubkey]
  end

  @spec requested_path(Phoenix.LiveView.Socket.t()) :: String.t()
  defp requested_path(socket) do
    case get_connect_info(socket, :uri) do
      %URI{path: path, query: query} when is_binary(path) and path != "" ->
        if query in [nil, ""], do: path, else: path <> "?" <> query

      _ ->
        "/"
    end
  end
end
