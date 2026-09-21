defmodule Rss2Nostr.Processing.HtmlToMarkdown.TrackingParams do
  @moduledoc false

  require Logger

  # Substack email links add isFreemail, triedRedirect, publication_id,
  # post_id, and r. mrfcid / ref / fbclid are click and referrer ids.
  # Any utm_* key is tracking, including ones not listed here.
  @tracking_params ~w(
    _ dmcid fbclid fbc f_tid igshid isfreemail mrfcid originalreferrer
    post_id publication_id r ref ref_src triedredirect
    utm_source utm_medium utm_campaign utm_term utm_content
    wt_zmc xing_share mc_cid mc_eid
  )

  @spec remove(String.t() | any()) :: String.t()
  def remove(url) when is_binary(url) do
    uri = URI.parse(url)

    case uri.query do
      nil ->
        URI.to_string(uri)

      query when is_binary(query) ->
        cleaned_query =
          query
          |> URI.decode_query()
          |> Enum.reject(fn {key, _} -> tracking_param?(key) end)
          |> URI.encode_query()

        new_query = if cleaned_query == "", do: nil, else: cleaned_query
        %{uri | query: new_query} |> URI.to_string()
    end
  rescue
    e ->
      Logger.debug("Failed to remove tracking params from URL: #{inspect(e)}")
      url
  end

  def remove(url), do: url

  @doc false
  # A space inside a query (`post-email title&publication_id=…`) leaves the
  # rest of the tracking string sitting after the link.
  @spec dangling_query?(String.t()) :: boolean()
  def dangling_query?(tail) when is_binary(tail) do
    parts = String.split(tail, "&", trim: true)

    keys =
      Enum.flat_map(parts, fn part ->
        case String.split(part, "=", parts: 2) do
          [key, _] -> [key]
          _ -> []
        end
      end)

    keys != [] and Enum.all?(keys, &tracking_param?/1) and
      Enum.all?(parts, fn part ->
        case String.split(part, "=", parts: 2) do
          [_key, _value] -> true
          [token] -> String.match?(token, ~r/^[A-Za-z0-9_%.-]+$/)
          _ -> false
        end
      end)
  end

  @spec tracking_param?(String.t()) :: boolean()
  defp tracking_param?(key) when is_binary(key) do
    key = String.downcase(key)
    String.starts_with?(key, "utm_") or key in @tracking_params
  end
end
