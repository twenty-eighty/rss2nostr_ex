defmodule Rss2Nostr.Nostr.Publisher.RelayPublish do
  @moduledoc false

  alias Rss2Nostr.Nostr.{NIP19, Relay}
  alias Rss2Nostr.Nostr.Publisher.{Gap, Identifiers}

  @type relay_failure :: %{url: String.t(), error: String.t()}

  @type publish_part_result :: %{
          success: boolean(),
          event_id: String.t() | nil,
          naddr: String.t() | nil,
          successful_relays: [String.t()],
          failed_relays: [relay_failure()]
        }

  @spec publish_signed_event(map(), integer(), String.t(), [String.t()], non_neg_integer()) ::
          publish_part_result()
  def publish_signed_event(signed_event, kind, pubkey_hex, relays, min_success) do
    results = publish_with_rate_limit_retry(relays, signed_event)

    {successful, failed} =
      Enum.reduce(results, {[], []}, fn {url, result}, {success, fail} ->
        case result do
          :ok ->
            {[url | success], fail}

          {:error, reason} ->
            {success, [%{url: url, error: Relay.format_error(reason)} | fail]}

          reason ->
            {success, [%{url: url, error: Relay.format_error(reason)} | fail]}
        end
      end)

    identifier = Identifiers.from_event(signed_event)

    naddr =
      case NIP19.encode_naddr(kind, pubkey_hex, identifier, successful) do
        {:ok, naddr} -> naddr
        _ -> nil
      end

    %{
      success: length(successful) >= min_success,
      event_id: signed_event.id,
      naddr: naddr,
      successful_relays: successful,
      failed_relays: failed
    }
  end

  @spec publish_with_rate_limit_retry([String.t()], map()) :: [{String.t(), term()}]
  def publish_with_rate_limit_retry(relays, signed_event) do
    results = Relay.publish_to_relays(relays, signed_event)

    {ok, limited} =
      Enum.split_with(results, fn {_url, result} -> not rate_limited_result?(result) end)

    case limited do
      [] ->
        results

      limited ->
        gap = Gap.publish_gap_ms()
        if gap > 0, do: Process.sleep(gap)

        retried =
          limited
          |> Enum.map(&elem(&1, 0))
          |> Relay.publish_to_relays(signed_event)

        ok ++ retried
    end
  end

  defp rate_limited_result?(:ok), do: false
  defp rate_limited_result?({:error, reason}), do: Relay.rate_limited?(reason)
  defp rate_limited_result?(reason), do: Relay.rate_limited?(reason)
end
