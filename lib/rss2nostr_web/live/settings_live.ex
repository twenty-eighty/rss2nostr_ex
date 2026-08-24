defmodule Rss2NostrWeb.SettingsLive do
  @moduledoc false

  use Rss2NostrWeb, :live_view

  alias Rss2Nostr.Nostr.NIP19
  alias Rss2Nostr.Web.API.Settings
  alias Rss2Nostr.Web.Auth

  @impl true
  def mount(_params, _session, socket) do
    settings = Settings.get()

    {:ok,
     socket
     |> assign(:page_title, "Settings")
     |> assign(:active_nav, "settings")
     |> assign(:nsec_configured, settings.nostr_nsec_configured)
     |> assign(:relays, settings.relays)
     |> assign(:upload_endpoint, settings.upload_endpoint)
     |> assign(:admin_keys, admin_keys())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h1>Settings</h1>

    <div class="settings-section">
      <h2>Nostr Configuration</h2>
      <div class="setting-item">
        <label>Private Key (NOSTR_NSEC)</label>
        <%= if @nsec_configured do %>
          <span class="badge badge-success">Configured</span>
        <% else %>
          <span class="badge badge-warning">Not Configured</span>
        <% end %>
        <p class="help-text">
          Set <code>NOSTR_NSEC</code> in <code>.env</code> to sign and NIP-44-encrypt NIP-37 drafts.
          Image uploads use a source nsec or bunker when configured; the app key is
          only a fallback for draft sources that also have an intended author pubkey.
        </p>
      </div>
    </div>

    <div class="settings-section">
      <h2>Relays</h2>
      <p>
        Draft sources always use the draft list. Article and video sources use the public list.
        Setup vs automated only controls the scheduler.
      </p>

      <h3>Draft relays</h3>
      <p class="help-text">
        Used for NIP-37 drafts (Pareto client). Set with <code>NOSTR_RELAYS_DRAFT</code>.
        Falls back to the test list if empty.
      </p>
      <.relay_list relays={@relays.draft} empty="None configured; using test relays" />

      <h3>Test relays</h3>
      <p class="help-text">
        Fallback when the draft list is empty. Set with <code>NOSTR_RELAYS_TEST</code> (or <code>NOSTR_RELAYS</code>).
      </p>
      <.relay_list relays={@relays.test} />

      <h3>Public relays</h3>
      <p class="help-text">
        Used for article and video sources, and as the inbox fallback for staging DMs
        when the recipient’s NIP-05 response lists no relays. Set with <code>NOSTR_RELAYS_PUBLIC</code>.
      </p>
      <.relay_list relays={@relays.public} />

      <h3>DM relays</h3>
      <p class="help-text">
        Extra relays always used when sending NIP-17 staging DMs, in addition to the
        recipient’s NIP-05 relays (or the public list if none are advertised).
        Set with <code>NOSTR_RELAYS_INBOX</code>.
      </p>
      <.relay_list
        relays={Map.get(@relays, :inbox, [])}
        empty="None configured; DMs use NIP-05 or public relays only"
      />
    </div>

    <div class="settings-section">
      <h2>Scheduler Intervals</h2>
      <p>Default task intervals (configurable in <code>config/config.exs</code>):</p>
      <table class="table">
        <tr><th>Task</th><th>Interval</th></tr>
        <tr><td>Import</td><td>15 minutes</td></tr>
        <tr><td>Process</td><td>5 minutes</td></tr>
        <tr><td>Export</td><td>10 minutes</td></tr>
        <tr><td>Cleanup</td><td>1 hour</td></tr>
      </table>
    </div>

    <div class="settings-section">
      <h2>Blossom Image Server</h2>
      <%= if @upload_endpoint do %>
        <p>Images are uploaded with Blossom (<code>PUT /upload</code>) to this server only:</p>
        <ul>
          <li><code>{@upload_endpoint}</code></li>
        </ul>
        <p class="help-text">
          Uploads are signed with the source nsec or bunker, or with
          <code>NOSTR_NSEC</code> for draft sources that have a pubkey. If upload
          fails, the article stays in <em>pending images</em> so the remaining
          uploads can be finished.
        </p>
      <% else %>
        <p>No <code>NOSTR_UPLOAD_ENDPOINT</code> is set.</p>
        <p class="help-text">
          Set it in <code>.env</code> to a Blossom server. Articles with images stay in
          <em>pending images</em> until the endpoint is configured and upload succeeds.
        </p>
      <% end %>
    </div>

    <div class="settings-section">
      <h2>Admin access (NIP-07)</h2>
      <p class="help-text">
        The web UI only accepts logins from these public keys, via a
        <a href="https://nips.nostr.com/7" target="_blank" rel="noopener">NIP-07</a>
        browser extension. Set <code>ADMIN_NOSTR_PUBKEYS</code> in <code>.env</code>.
      </p>
      <ul>
        <%= if @admin_keys == [] do %>
          <li class="empty-state">None configured</li>
        <% else %>
          <li :for={key <- @admin_keys}><code>{key}</code></li>
        <% end %>
      </ul>
    </div>

    <div class="settings-section">
      <h2>About</h2>
      <p><strong>RSS2Nostr</strong> v0.1.0</p>
      <p>Import RSS/Atom feeds and publish to Nostr as long-form content (NIP-23).</p>
      <p>
        <a href="https://github.com/razue/rss2nostr" target="_blank">GitHub</a>
      </p>
    </div>
    """
  end

  attr :relays, :list, required: true
  attr :empty, :string, default: "None configured"

  defp relay_list(assigns) do
    ~H"""
    <ul>
      <%= if @relays == [] do %>
        <li class="empty-state">{@empty}</li>
      <% else %>
        <li :for={url <- @relays}><code>{url}</code></li>
      <% end %>
    </ul>
    """
  end

  defp admin_keys do
    Enum.map(Auth.pubkeys(), fn hex ->
      case NIP19.encode_npub(hex) do
        {:ok, encoded} -> encoded
        _ -> hex
      end
    end)
  end
end
