defmodule Rss2Nostr do
  @moduledoc """
  RSS2Nostr - Import RSS/Atom feeds and publish as Nostr long-form content (NIP-23).

  This application provides:
  - RSS/Atom feed importing
  - HTML to Markdown conversion
  - Image extraction and NIP-96 upload
  - Nostr event creation and multi-relay publishing
  - Support for local and remote (NIP-46 Bunker) signing
  """

  @doc """
  Returns the configured Nostr relays.
  """
  def nostr_relays do
    Application.get_env(:rss2nostr, :nostr)[:relays] || []
  end

  @doc """
  Returns the configured Nostr private key.
  """
  def nostr_private_key do
    Application.get_env(:rss2nostr, :nostr)[:private_key]
  end

  @doc """
  Returns the configured Nostr public key.
  """
  def nostr_public_key do
    Application.get_env(:rss2nostr, :nostr)[:public_key]
  end

  @doc """
  Returns the configured NIP-96 upload endpoint.
  """
  def upload_endpoint do
    Application.get_env(:rss2nostr, :nostr)[:upload_endpoint]
  end

  @doc """
  Returns the configured NIP-46 bunker connection string.
  """
  def bunker_connection do
    Application.get_env(:rss2nostr, :nostr)[:bunker_connection]
  end

  @doc """
  Returns the default import language.
  """
  def default_language do
    Application.get_env(:rss2nostr, :import)[:default_language] || "de"
  end
end
