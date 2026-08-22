defmodule Rss2Nostr.Processing.HtmlToMarkdown.TrackingParams do
  @moduledoc false

  require Logger

  @tracking_params ~w(
    _ dmcid fbclid fbc f_tid igshid originalReferrer ref_src
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
          |> Enum.reject(fn {key, _} ->
            Enum.any?(@tracking_params, &(String.downcase(key) == &1))
          end)
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
end
