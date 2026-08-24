defmodule Rss2Nostr.TzdataHTTPClient do
  @moduledoc false
  @behaviour Tzdata.HTTPClient

  alias Rss2Nostr.HTTP

  @type tz_headers :: [{String.t(), String.t()}]
  @type tz_options :: keyword()

  @impl true
  @spec get(String.t(), tz_headers(), tz_options()) ::
          {:ok, {non_neg_integer(), tz_headers(), binary()}} | {:error, term()}
  def get(url, headers, options) do
    case HTTP.get(url, http_opts(headers, options)) do
      {:ok, %{status: status, headers: resp_headers, body: body}} ->
        {:ok, {status, HTTP.headers_to_list(resp_headers), body}}

      {:error, exception} ->
        {:error, exception}
    end
  end

  @impl true
  @spec head(String.t(), tz_headers(), tz_options()) ::
          {:ok, {non_neg_integer(), tz_headers()}} | {:error, term()}
  def head(url, headers, options) do
    case HTTP.head(url, http_opts(headers, options)) do
      {:ok, %{status: status, headers: resp_headers}} ->
        {:ok, {status, HTTP.headers_to_list(resp_headers)}}

      {:error, exception} ->
        {:error, exception}
    end
  end

  @spec http_opts(tz_headers(), tz_options()) :: keyword()
  defp http_opts(headers, options) do
    follow_redirect = Keyword.get(options, :follow_redirect, true)

    [
      headers: headers,
      receive_timeout: 60_000,
      redirect: follow_redirect,
      raw: true
    ]
  end
end
