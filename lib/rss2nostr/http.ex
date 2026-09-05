defmodule Rss2Nostr.HTTP do
  @moduledoc false

  alias Rss2Nostr.HTTP.SafeURL
  alias Rss2Nostr.Processing.ImageExtractor.Urls, as: MediaUrls

  @user_agent "RSS2Nostr/0.1 (Elixir)"
  @max_redirects 3

  @type headers :: %{String.t() => String.t() | [String.t()]} | [{String.t(), String.t()}]

  @type response :: %{status: integer(), body: binary(), headers: headers()}

  @spec get(String.t(), keyword()) :: {:ok, response()} | {:error, Exception.t() | atom()}
  def get(url, opts \\ []), do: request(Keyword.merge(opts, method: :get, url: url))

  @spec head(String.t(), keyword()) :: {:ok, response()} | {:error, Exception.t() | atom()}
  def head(url, opts \\ []), do: request(Keyword.merge(opts, method: :head, url: url))

  @spec post(String.t(), keyword()) :: {:ok, response()} | {:error, Exception.t() | atom()}
  def post(url, opts \\ []), do: request(Keyword.merge(opts, method: :post, url: url))

  @spec put(String.t(), keyword()) :: {:ok, response()} | {:error, Exception.t() | atom()}
  def put(url, opts \\ []), do: request(Keyword.merge(opts, method: :put, url: url))

  @spec header(headers(), String.t()) :: String.t() | nil
  def header(headers, name) when is_map(headers) do
    key = String.downcase(name)

    case Map.get(headers, key) do
      [value | _] -> value
      value when is_binary(value) -> value
      _ -> nil
    end
  end

  def header(headers, name) when is_list(headers) do
    name_lower = String.downcase(name)

    case Enum.find(headers, fn {key, _} -> String.downcase(to_string(key)) == name_lower end) do
      {_, value} -> to_string(value)
      nil -> nil
    end
  end

  @spec headers_to_list(headers()) :: [{String.t(), String.t()}]
  def headers_to_list(headers) when is_map(headers) do
    Enum.flat_map(headers, fn {key, values} ->
      Enum.map(List.wrap(values), fn value -> {to_string(key), to_string(value)} end)
    end)
  end

  def headers_to_list(headers) when is_list(headers) do
    Enum.map(headers, fn {key, value} -> {to_string(key), to_string(value)} end)
  end

  @spec request(keyword()) :: {:ok, response()} | {:error, Exception.t() | atom()}
  defp request(opts) do
    url = opts |> Keyword.fetch!(:url) |> MediaUrls.encode_http_url()

    case SafeURL.validate(url) do
      :ok ->
        do_request(Keyword.put(opts, :url, url))

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec do_request(keyword()) :: {:ok, response()} | {:error, Exception.t() | atom()}
  defp do_request(opts) do
    {:ok, _} = Application.ensure_all_started(:req)

    default_timeout = Application.get_env(:rss2nostr, :http_receive_timeout, 30_000)
    default_retry = Application.get_env(:rss2nostr, :http_retry, true)

    {receive_timeout, opts} = Keyword.pop(opts, :receive_timeout, default_timeout)

    req_opts =
      opts
      |> Keyword.put(:receive_timeout, receive_timeout)
      |> Keyword.put_new(:retry, default_retry)
      |> Keyword.put_new(:decode_body, false)
      |> Keyword.put_new(:compressed, true)
      |> Keyword.put_new(:redirect, true)
      |> Keyword.put_new(:max_redirects, @max_redirects)
      |> Keyword.update(:headers, [{"user-agent", @user_agent}], &ensure_user_agent/1)

    request =
      Req.new(req_opts)
      |> Req.Request.prepend_request_steps(
        encode_url: &encode_url/1,
        ssrf_check: &ssrf_check/1
      )

    case Req.request(request) do
      {:ok, %Req.Response{} = response} ->
        {:ok, %{status: response.status, body: response.body, headers: response.headers}}

      {:error, exception} ->
        {:error, exception}
    end
  rescue
    exception in [ArgumentError] ->
      {:error, exception}
  end

  # Re-encode after each redirect: some servers put literal spaces in Location.
  @spec encode_url(Req.Request.t()) :: Req.Request.t()
  defp encode_url(%Req.Request{url: %URI{} = uri} = request) do
    encoded = uri |> URI.to_string() |> MediaUrls.encode_http_url() |> URI.parse()
    %{request | url: encoded}
  end

  @spec ssrf_check(Req.Request.t()) :: Req.Request.t()
  defp ssrf_check(%Req.Request{} = request) do
    url = URI.to_string(request.url)

    case SafeURL.validate(url) do
      :ok ->
        request

      {:error, reason} ->
        Req.Request.halt(request, %RuntimeError{message: "blocked URL (#{reason})"})
    end
  end

  @spec ensure_user_agent([{String.t(), String.t()}]) :: [{String.t(), String.t()}]
  defp ensure_user_agent(headers) do
    has_ua? =
      Enum.any?(headers, fn {key, _} -> String.downcase(to_string(key)) == "user-agent" end)

    if has_ua?, do: headers, else: [{"user-agent", @user_agent} | headers]
  end
end
