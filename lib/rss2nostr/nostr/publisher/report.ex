defmodule Rss2Nostr.Nostr.Publisher.Report do
  @moduledoc false

  @type relay_failure :: %{url: String.t(), error: String.t()}

  @spec format_report([String.t()], [relay_failure()]) :: String.t()
  def format_report(successful, failed) do
    [format_reached(successful), format_missed(failed)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  @spec report_or_failure(String.t()) :: String.t()
  def report_or_failure(""), do: "Publish failed"
  def report_or_failure(report), do: report

  @spec merge_failures([relay_failure()]) :: [relay_failure()]
  def merge_failures(failures) do
    failures
    |> Enum.reverse()
    |> Enum.uniq_by(& &1.url)
    |> Enum.reverse()
  end

  @spec format_reached([String.t()]) :: String.t() | nil
  defp format_reached([]), do: nil

  defp format_reached(urls) do
    "Reached #{length(urls)} #{relay_word(length(urls))}: #{Enum.map_join(urls, ", ", &relay_label/1)}."
  end

  @spec format_missed([relay_failure()]) :: String.t() | nil
  defp format_missed([]), do: nil

  defp format_missed(failed) do
    items =
      Enum.map_join(failed, "; ", fn
        %{url: url, error: error} -> "#{relay_label(url)} (#{error})"
        {url, error} -> "#{relay_label(url)} (#{error})"
      end)

    "Missed #{length(failed)}: #{items}."
  end

  @spec relay_word(integer()) :: String.t()
  defp relay_word(1), do: "relay"
  defp relay_word(_), do: "relays"

  @spec relay_label(String.t()) :: String.t()
  defp relay_label(url) do
    case URI.parse(to_string(url)) do
      %URI{host: host} when is_binary(host) and host != "" -> host
      _ -> to_string(url)
    end
  end
end
