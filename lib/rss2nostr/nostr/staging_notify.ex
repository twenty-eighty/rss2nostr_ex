defmodule Rss2Nostr.Nostr.StagingNotify do
  @moduledoc """
  Sends a NIP-17 DM when an article enters staging.
  """

  require Logger

  alias Rss2Nostr.Nostr.{InboxRelays, NIP17, Signer}
  alias Rss2Nostr.Nostr.Relay
  alias Rss2Nostr.Posts.Post
  alias Rss2Nostr.Sources.Source

  @type notify_error ::
          :notify_failed | :no_app_private_key | :no_relays | Rss2Nostr.Nostr.NIP17.wrap_error()

  @spec maybe_notify(Post.t()) :: :ok | {:error, notify_error()}
  def maybe_notify(%Post{} = post) do
    post = Rss2Nostr.Posts.preload_source(post)
    source = post.source

    cond do
      not match?(%Source{}, source) ->
        :ok

      not present?(source.notify_pubkey) ->
        :ok

      true ->
        send_dm(post, source)
    end
  end

  @spec send_dm(Post.t(), Source.t()) :: :ok | {:error, notify_error()}
  defp send_dm(post, source) do
    with {:ok, {:private_key, key}} <- Signer.app_signer(),
         {:ok, wrap} <-
           NIP17.wrap(message(post, source), key, source.notify_pubkey, subject: "Staging"),
         relays when relays != [] <- InboxRelays.for_pubkey(source.notify_pubkey) do
      results = Relay.publish_to_relays(relays, wrap)
      ok? = Enum.any?(results, fn {_url, result} -> result == :ok end)

      if ok? do
        Logger.info("Staging DM sent for post #{post.id}")
        :ok
      else
        Logger.warning("Staging DM failed for post #{post.id}: #{inspect(results)}")
        {:error, :notify_failed}
      end
    else
      {:error, :no_app_private_key} ->
        Logger.warning("Staging DM skipped for post #{post.id}: NOSTR_NSEC is not set")
        {:error, :no_app_private_key}

      {:error, reason} ->
        Logger.warning("Staging DM skipped for post #{post.id}: #{inspect(reason)}")
        {:error, reason}

      [] ->
        Logger.warning("Staging DM skipped for post #{post.id}: no relays")
        {:error, :no_relays}
    end
  end

  @spec message(Post.t(), Source.t()) :: String.t()
  def message(post, source) do
    [
      "Staging: #{source.name}",
      post.title || "Untitled",
      post.source_url,
      timing(source)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  @spec timing(Source.t()) :: String.t()
  defp timing(source) do
    hold = source.staging_hold_minutes || 0

    cond do
      not Source.automated?(source) -> "Waiting for manual publish."
      hold <= 0 -> "Ready to auto-publish."
      rem(hold, 60) == 0 -> "Auto-publishes in #{div(hold, 60)}h."
      true -> "Auto-publishes in #{hold} minutes."
    end
  end

  @spec present?(String.t() | nil) :: boolean()
  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: false
end
