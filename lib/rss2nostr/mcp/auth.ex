defmodule Rss2Nostr.MCP.Auth do
  @moduledoc false

  import Plug.Conn

  alias Rss2Nostr.Web.RateLimit

  @rate_limit 120
  @rate_window_ms 60_000

  @spec call(Plug.Conn.t()) :: Plug.Conn.t()
  def call(conn) do
    cond do
      not rate_limit_ok?(conn) ->
        unauthorized(conn, 429, "rate_limited")

      token_ok?(conn) ->
        conn

      loopback?(conn) and is_nil(Rss2Nostr.MCP.token()) and Rss2Nostr.MCP.allow_loopback?() ->
        conn

      true ->
        unauthorized(conn, 401, "unauthorized")
    end
  end

  defp unauthorized(conn, status, error) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(%{error: error}))
    |> halt()
  end

  defp rate_limit_ok?(conn) do
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()
    RateLimit.allow?({:mcp, ip}, @rate_limit, @rate_window_ms)
  end

  defp token_ok?(conn) do
    case Rss2Nostr.MCP.token() do
      token when is_binary(token) and token != "" ->
        case bearer(conn) do
          provided when is_binary(provided) ->
            Plug.Crypto.secure_compare(provided, token)

          _ ->
            false
        end

      _ ->
        false
    end
  end

  defp bearer(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> token
      ["bearer " <> token] -> token
      _ -> nil
    end
  end

  defp loopback?(conn) do
    case conn.remote_ip do
      {127, 0, 0, _} -> true
      {0, 0, 0, 0, 0, 0, 0, 1} -> true
      {0, 0, 0, 0, 0, 65_535, 32512, 1} -> true
      _ -> false
    end
  end
end
