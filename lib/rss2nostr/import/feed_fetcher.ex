defmodule Rss2Nostr.Import.FeedFetcher do
  @moduledoc """
  Fetches RSS/Atom feeds from URLs.
  """

  require Logger

  alias Rss2Nostr.HTTP

  @user_agent "RSS2Nostr/0.1 (Elixir)"
  @timeout 30_000

  @doc """
  Fetches a feed from the given URL.
  Returns {:ok, body} or {:error, reason}.
  """
  @spec fetch(String.t() | any()) :: {:ok, String.t()} | {:error, String.t()}
  def fetch(url) when is_binary(url) do
    request(url,
      headers: [
        {"user-agent", @user_agent},
        {"accept", "application/rss+xml, application/atom+xml, application/xml, text/xml, */*"}
      ]
    )
  end

  def fetch(_), do: {:error, "Invalid URL"}

  @doc """
  Fetches content from an article URL (for full content extraction).
  """
  @spec fetch_article(String.t() | any()) :: {:ok, String.t()} | {:error, String.t()}
  def fetch_article(url) when is_binary(url) do
    request(url,
      headers: [
        {"user-agent", @user_agent},
        {"accept", "text/html, application/xhtml+xml, */*"}
      ]
    )
  end

  def fetch_article(_), do: {:error, "Invalid URL"}

  defp request(url, opts) do
    Logger.debug("Fetching #{url}")

    case HTTP.get(url, Keyword.merge(opts, receive_timeout: @timeout, retry: false)) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, ensure_utf8(body)}

      {:ok, %{status: status_code}} ->
        {:error, "HTTP #{status_code}"}

      {:error, exception} ->
        {:error, "Request failed: #{Exception.message(exception)}"}
    end
  end

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
