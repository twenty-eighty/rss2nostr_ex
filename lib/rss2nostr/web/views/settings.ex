defmodule Rss2Nostr.Web.Views.Settings do
  @moduledoc """
  Views for application settings.
  """

  alias Rss2Nostr.Web.Views.Layout
  alias Rss2Nostr.Web.Auth
  alias Rss2Nostr.Nostr.{Blossom, Relays, NIP19}

  def index do
    nsec_configured = System.get_env("NOSTR_NSEC") != nil
    relays = Relays.all()

    content = """
    <h1>Settings</h1>

    <div class="settings-section">
      <h2>Nostr Configuration</h2>

      <div class="setting-item">
        <label>Private Key (NOSTR_NSEC)</label>
        #{if nsec_configured do
      "<span class=\"badge badge-success\">Configured</span>"
    else
      "<span class=\"badge badge-warning\">Not Configured</span>"
    end}
        <p class="help-text">
          Set <code>NOSTR_NSEC</code> in <code>.env</code> to sign and NIP-44-encrypt NIP-37 drafts.
          Image uploads use a source nsec or bunker when configured; the app key is
          only a fallback for draft sources that also have an intended author pubkey.
        </p>
      </div>
    </div>

    <div class="settings-section">
      <h2>Relays</h2>
      <p>Draft sources always use the draft list. Article sources use the public list when marked public, otherwise the test list. Setup vs automated only controls the scheduler.</p>

      <h3>Draft relays</h3>
      <p class="help-text">Used for NIP-37 drafts (Pareto client). Set with <code>NOSTR_RELAYS_DRAFT</code>. Falls back to the test list if empty.</p>
      <ul>
        #{draft_relay_items(relays.draft)}
      </ul>

      <h3>Test relays</h3>
      <p class="help-text">Used for article sources that are not marked public. Set with <code>NOSTR_RELAYS_TEST</code> (or <code>NOSTR_RELAYS</code>).</p>
      <ul>
        #{relay_items(relays.test)}
      </ul>

      <h3>Public relays</h3>
      <p class="help-text">
        Used for article sources marked public, and as the inbox fallback for staging DMs
        when the recipient’s NIP-05 response lists no relays. Set with <code>NOSTR_RELAYS_PUBLIC</code>.
      </p>
      <ul>
        #{relay_items(relays.public)}
      </ul>

      <h3>DM relays</h3>
      <p class="help-text">
        Extra relays always used when sending NIP-17 staging DMs, in addition to the
        recipient’s NIP-05 relays (or the public list if none are advertised).
        Set with <code>NOSTR_RELAYS_INBOX</code>.
      </p>
      <ul>
        #{inbox_relay_items(Map.get(relays, :inbox, []))}
      </ul>
    </div>

    <div class="settings-section">
      <h2>Scheduler Intervals</h2>
      <p>Default task intervals (configurable in <code>config/config.exs</code>):</p>
      <table class="table">
        <tr>
          <th>Task</th>
          <th>Interval</th>
        </tr>
        <tr>
          <td>Import</td>
          <td>15 minutes</td>
        </tr>
        <tr>
          <td>Process</td>
          <td>5 minutes</td>
        </tr>
        <tr>
          <td>Export</td>
          <td>10 minutes</td>
        </tr>
        <tr>
          <td>Cleanup</td>
          <td>24 hours</td>
        </tr>
      </table>
    </div>

    <div class="settings-section">
      <h2>Blossom Image Server</h2>
      #{blossom_section()}
    </div>

    <div class="settings-section">
      <h2>Admin access (NIP-07)</h2>
      <p class="help-text">
        The web UI only accepts logins from these public keys, via a
        <a href="https://nips.nostr.com/7" target="_blank" rel="noopener">NIP-07</a>
        browser extension. Set <code>ADMIN_NOSTR_PUBKEYS</code> in <code>.env</code>.
      </p>
      <ul>
        #{admin_key_items()}
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

    Layout.render("Settings", content, active_nav: "settings")
  end

  defp draft_relay_items([]),
    do: "<li class=\"empty-state\">None configured; using test relays</li>"

  defp draft_relay_items(relays), do: relay_items(relays)

  defp inbox_relay_items([]),
    do: "<li class=\"empty-state\">None configured; DMs use NIP-05 or public relays only</li>"

  defp inbox_relay_items(relays), do: relay_items(relays)

  defp relay_items([]), do: "<li class=\"empty-state\">None configured</li>"

  defp relay_items(relays) do
    Enum.map_join(relays, "", fn url -> "<li><code>#{escape_html(url)}</code></li>" end)
  end

  defp admin_key_items do
    case Auth.pubkeys() do
      [] ->
        "<li class=\"empty-state\">None configured</li>"

      keys ->
        Enum.map_join(keys, "", fn hex ->
          npub =
            case NIP19.encode_npub(hex) do
              {:ok, encoded} -> encoded
              _ -> hex
            end

          "<li><code>#{escape_html(npub)}</code></li>"
        end)
    end
  end

  defp blossom_section do
    case Blossom.configured_server() do
      nil ->
        """
        <p>No <code>NOSTR_UPLOAD_ENDPOINT</code> is set.</p>
        <p class="help-text">
          Set it in <code>.env</code> to a Blossom server. Articles with images stay in
          <em>pending images</em> until the endpoint is configured and upload succeeds.
        </p>
        """

      endpoint ->
        """
        <p>Images are uploaded with Blossom (<code>PUT /upload</code>) to this server only:</p>
        <ul>
          <li><code>#{escape_html(endpoint)}</code></li>
        </ul>
        <p class="help-text">
          Uploads are signed with the source nsec or bunker, or with
          <code>NOSTR_NSEC</code> for draft sources that have a pubkey. If upload
          fails, the article stays in <em>pending images</em> so the remaining
          uploads can be finished.
        </p>
        """
    end
  end

  defp escape_html(str) when is_binary(str) do
    str
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp escape_html(nil), do: ""
end
