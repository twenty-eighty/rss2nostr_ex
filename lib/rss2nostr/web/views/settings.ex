defmodule Rss2Nostr.Web.Views.Settings do
  @moduledoc """
  Views for application settings.
  """

  alias Rss2Nostr.Web.Views.Layout

  def index do
    nsec_configured = System.get_env("NOSTR_NSEC") != nil

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
          Set the <code>NOSTR_NSEC</code> environment variable to enable automatic export.
          The key should be in nsec or hex format.
        </p>
      </div>
    </div>

    <div class="settings-section">
      <h2>Default Relays</h2>
      <p>The following relays are used for publishing:</p>
      <ul>
        <li><code>wss://relay.damus.io</code></li>
        <li><code>wss://nos.lol</code></li>
        <li><code>wss://relay.nostr.band</code></li>
      </ul>
      <p class="help-text">
        Configure additional relays in <code>config/config.exs</code> or via the CLI.
      </p>
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
      </table>
    </div>

    <div class="settings-section">
      <h2>NIP-96 Image Servers</h2>
      <p>Available image hosting servers:</p>
      <ul>
        <li><code>https://nostr.build</code> (default)</li>
        <li><code>https://nostrcheck.me</code></li>
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
end
