defmodule Rss2NostrWeb.CoreComponents do
  @moduledoc false

  use Phoenix.Component

  import Rss2NostrWeb.LiveHelpers

  attr :status, :integer, required: true
  attr :rest, :global

  def status_badge(assigns) do
    ~H"""
    <span class={"badge #{status_class(@status)}"} {@rest}>{status_label(@status)}</span>
    """
  end

  attr :source, :map, required: true

  def source_author(assigns) do
    pubkey = author_pubkey(assigns.source)

    assigns =
      assigns
      |> assign(:pubkey, pubkey)
      |> assign(:placeholder, avatar_placeholder())

    ~H"""
    <div class="source-author">
      <img
        class="source-avatar"
        src={@placeholder}
        alt=""
        width="32"
        height="32"
        data-pubkey={@pubkey}
        data-created-at="0"
      />
      <span>{@source.name}</span>
    </div>
    """
  end

  attr :member, :any, default: nil

  def follow_list_badge(assigns) do
    ~H"""
    <%= cond do %>
      <% @member == true -> %>
        <span class="badge badge-active" title="Author is on the configured follow list">Yes</span>
      <% @member == false -> %>
        <span class="badge badge-inactive" title="Author is not on the configured follow list">No</span>
      <% @member == :unknown -> %>
        <span
          class="badge badge-test"
          title="Signing key is set but the author pubkey could not be resolved. Open Publishing and re-save the nsec."
        >
          ?
        </span>
      <% true -> %>
        <span class="help-text" title="No author pubkey configured for this feed">—</span>
    <% end %>
    """
  end

  attr :field, :atom, required: true
  attr :errors, :map, default: %{}

  def field_error(assigns) do
    assigns = assign(assigns, :message, error_text(assigns.errors[assigns.field]))

    ~H"""
    <span :if={@message} class="error">{@message}</span>
    """
  end
end
