defmodule Rss2Nostr.Nostr.StagingNotify do
  @moduledoc """
  Sends a NIP-17 DM when an article reaches a state that will not advance
  automatically: staging for setup/manual sources, published for automated
  ones, or when media upload is given up.
  """

  require Logger

  alias Rss2Nostr.Nostr.{InboxRelays, NIP17, Signer}
  alias Rss2Nostr.Nostr.Relay
  alias Rss2Nostr.Posts.Post
  alias Rss2Nostr.Sources.Source

  @type notify_kind :: :staging | :published | :upload_failed

  @type notify_error ::
          :notify_failed | :no_app_private_key | :no_relays | Rss2Nostr.Nostr.NIP17.wrap_error()

  @doc """
  Notifies when an article enters staging and will wait for manual publish.
  Automated sources skip this — they notify on publish instead.
  """
  @spec maybe_notify_staging(Post.t()) :: :ok | {:error, notify_error()}
  def maybe_notify_staging(%Post{} = post), do: maybe_notify(post, :staging)

  @doc """
  Notifies when an automated source finishes publishing.
  Setup sources skip this — they were already notified at staging.
  """
  @spec maybe_notify_published(Post.t()) :: :ok | {:error, notify_error()}
  def maybe_notify_published(%Post{} = post), do: maybe_notify(post, :published)

  @doc """
  Notifies when media upload is given up. Sent for both setup and automated sources.
  """
  @spec maybe_notify_upload_failed(Post.t()) :: :ok | {:error, notify_error()}
  def maybe_notify_upload_failed(%Post{} = post), do: maybe_notify(post, :upload_failed)

  @doc false
  @spec maybe_notify(Post.t()) :: :ok | {:error, notify_error()}
  def maybe_notify(%Post{} = post), do: maybe_notify_staging(post)

  @spec maybe_notify(Post.t(), notify_kind()) :: :ok | {:error, notify_error()}
  def maybe_notify(%Post{} = post, kind)
      when kind in [:staging, :published, :upload_failed] do
    post = Rss2Nostr.Posts.preload_source(post)
    source = post.source

    cond do
      not match?(%Source{}, source) ->
        :ok

      not present?(source.notify_pubkey) ->
        :ok

      kind == :staging and Source.automated?(source) ->
        :ok

      kind == :published and not Source.automated?(source) ->
        :ok

      true ->
        send_dm(post, source, kind)
    end
  end

  @spec send_dm(Post.t(), Source.t(), notify_kind()) :: :ok | {:error, notify_error()}
  defp send_dm(post, source, kind) do
    subject = subject(kind)

    with {:ok, {:private_key, key}} <- Signer.app_signer(),
         {:ok, wrap} <-
           NIP17.wrap(message(post, source, kind), key, source.notify_pubkey, subject: subject),
         relays when relays != [] <- InboxRelays.for_pubkey(source.notify_pubkey) do
      results = Relay.publish_to_relays(relays, wrap)
      ok? = Enum.any?(results, fn {_url, result} -> result == :ok end)

      if ok? do
        Logger.info("#{subject} DM sent for post #{post.id}")
        :ok
      else
        Logger.warning("#{subject} DM failed for post #{post.id}: #{inspect(results)}")
        {:error, :notify_failed}
      end
    else
      {:error, :no_app_private_key} ->
        Logger.warning("#{subject} DM skipped for post #{post.id}: NOSTR_NSEC is not set")
        {:error, :no_app_private_key}

      {:error, reason} ->
        Logger.warning("#{subject} DM skipped for post #{post.id}: #{inspect(reason)}")
        {:error, reason}

      [] ->
        Logger.warning("#{subject} DM skipped for post #{post.id}: no relays")
        {:error, :no_relays}
    end
  end

  @spec subject(notify_kind()) :: String.t()
  defp subject(:staging), do: "Staging"
  defp subject(:published), do: "Published"
  defp subject(:upload_failed), do: "Upload failed"

  @spec message(Post.t(), Source.t()) :: String.t()
  def message(post, source), do: message(post, source, :staging)

  @spec message(Post.t(), Source.t(), notify_kind()) :: String.t()
  def message(post, source, kind) do
    [
      heading(source, kind),
      post.title || "Untitled",
      post.source_url,
      detail(post, source, kind)
    ]
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join("\n")
  end

  @spec heading(Source.t(), notify_kind()) :: String.t()
  defp heading(source, :staging), do: "Staging: #{source.name}"
  defp heading(source, :published), do: "Published: #{source.name}"
  defp heading(source, :upload_failed), do: "Upload failed: #{source.name}"

  @spec detail(Post.t(), Source.t(), notify_kind()) :: String.t()
  defp detail(_post, _source, :staging), do: "Waiting for manual publish."

  defp detail(post, _source, :published) do
    cond do
      present?(post.nostr_address) -> post.nostr_address
      present?(post.event_id) -> "Event: #{post.event_id}"
      true -> "Published."
    end
  end

  defp detail(post, _source, :upload_failed) do
    reason =
      if present?(post.last_error), do: post.last_error, else: "Media upload failed"

    "Content/media upload failed. #{reason}"
  end

  @spec present?(String.t() | nil) :: boolean()
  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: false
end
