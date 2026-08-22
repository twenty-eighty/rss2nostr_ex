defmodule Rss2Nostr.Web.Views.Sources.Tabs.Publishing do
  @moduledoc false

  alias Rss2Nostr.Nostr.Signer
  alias Rss2Nostr.Sources.Source
  alias Rss2Nostr.Web.Views.Sources.{Fields, Helpers}

  def publishing_tab(source, params, errors) do
    signer_ok? = Signer.configured?(source)

    """
    <form action="/sources/#{source.id}" method="POST" class="form form-wide">
      <input type="hidden" name="tab" value="publishing">
      #{Fields.publish_as_fields(params, source, errors)}
      #{Fields.fixed_hashtag_fields(params, source, errors)}
      #{Fields.excluded_hashtag_fields(params, source, errors)}
      #{Fields.staging_fields(params, source, errors)}
      #{Helpers.error_message(errors, :mode)}
      #{unless signer_ok? do
        "<p class=\"help-text\">Configure a signing key before switching to automated publishing. Use the Setup badge at the top once a key is set.</p>"
      else
        "<p class=\"help-text\">Use the Setup / Automated badge at the top of the page to change mode.</p>"
      end}
      <div class="form-actions">
        <button type="submit" class="btn btn-primary">Save publishing settings</button>
      </div>
    </form>
    """
  end


  def mode_badge(%Source{mode: "automated"} = source, tab) do
    mode_badge_form(source, tab, "setup", "Automated", "badge-processed", "Switch back to setup")
  end

  def mode_badge(source, tab) do
    if Signer.configured?(source) do
      mode_badge_form(
        source,
        tab,
        "automated",
        "Setup",
        "badge-test",
        "Switch to automated publishing"
      )
    else
      ~s(<a href="/sources/#{source.id}?tab=publishing" class="badge badge-test" title="Configure a signing key on the Publishing tab, then switch to automated">Setup</a>)
    end
  end


  defp mode_badge_form(source, tab, next_mode, label, class, title) do
    """
    <form action="/sources/#{source.id}" method="POST" class="inline-mode-form">
      <input type="hidden" name="tab" value="#{Helpers.escape_attr(tab)}">
      <button type="submit" name="mode" value="#{Helpers.escape_attr(next_mode)}" class="badge #{class}" title="#{Helpers.escape_attr(title)}">#{label}</button>
    </form>
    """
  end


end
