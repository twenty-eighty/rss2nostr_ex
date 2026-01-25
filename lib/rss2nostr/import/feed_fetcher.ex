defmodule Rss2Nostr.Import.FeedFetcher do
  @moduledoc """
  Fetches RSS/Atom feeds from URLs.
  """

  require Logger

  @user_agent "RSS2Nostr/0.1 (Elixir)"
  @timeout 30_000

  @doc """
  Fetches a feed from the given URL.
  Returns {:ok, body} or {:error, reason}.
  """
  @spec fetch(String.t() | any()) :: {:ok, String.t()} | {:error, String.t()}
  def fetch(url) when is_binary(url) do
    headers = [
      {"User-Agent", @user_agent},
      {"Accept", "application/rss+xml, application/atom+xml, application/xml, text/xml, */*"}
    ]

    options = [
      timeout: @timeout,
      recv_timeout: @timeout,
      follow_redirect: true,
      max_redirect: 5
    ]

    Logger.debug("Fetching feed from #{url}")

    case HTTPoison.get(url, headers, options) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, ensure_utf8(body)}

      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        {:error, "HTTP #{status_code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  def fetch(_), do: {:error, "Invalid URL"}

  @doc """
  Fetches content from an article URL (for full content extraction).
  """
  @spec fetch_article(String.t() | any()) :: {:ok, String.t()} | {:error, String.t()}
  def fetch_article(url) when is_binary(url) do
    headers = [
      {"User-Agent", @user_agent},
      {"Accept", "text/html, application/xhtml+xml, */*"}
    ]

    options = [
      timeout: @timeout,
      recv_timeout: @timeout,
      follow_redirect: true,
      max_redirect: 5
    ]

    Logger.debug("Fetching article from #{url}")

    case HTTPoison.get(url, headers, options) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, ensure_utf8(body)}

      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        {:error, "HTTP #{status_code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  def fetch_article(_), do: {:error, "Invalid URL"}

  # Ensure the body is valid UTF-8
  defp ensure_utf8(body) when is_binary(body) do
    case :unicode.characters_to_binary(body, :utf8) do
      {:error, _, _} ->
        # Try latin1 to utf8 conversion
        :unicode.characters_to_binary(body, :latin1)

      {:incomplete, _, _} ->
        # Remove invalid bytes
        body
        |> String.codepoints()
        |> Enum.filter(&String.valid?/1)
        |> Enum.join()

      valid_utf8 ->
        valid_utf8
    end
  end
end
