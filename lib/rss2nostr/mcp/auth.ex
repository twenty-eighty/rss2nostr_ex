defmodule Rss2Nostr.MCP.Auth do
  @moduledoc false

  import Plug.Conn

  @spec call(Plug.Conn.t()) :: Plug.Conn.t()
  def call(conn) do
    cond do
      token_ok?(conn) ->
        conn

      loopback?(conn) and is_nil(Rss2Nostr.MCP.token()) ->
        conn

      true ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{error: "unauthorized"}))
        |> halt()
    end
  end

  defp token_ok?(conn) do
    case Rss2Nostr.MCP.token() do
      token when is_binary(token) and token != "" ->
        bearer(conn) == token

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
