defmodule Rss2Nostr.Web.Views.Sources.Fields do
  @moduledoc false

  alias Rss2Nostr.Nostr.Signer
  alias Rss2Nostr.Web.Views.Sources.{Helpers, Scripts}

  def fixed_hashtag_fields(params, source, errors) do
    tags =
      params["fixed_hashtags"] ||
        (source && Enum.join(source.fixed_hashtags || [], ", ")) ||
        ""

    tags =
      case tags do
        list when is_list(list) -> Enum.join(list, ", ")
        value -> to_string(value)
      end

    """
    <div class="form-group">
      <label for="fixed_hashtags">Fixed hashtags</label>
      <input type="text" id="fixed_hashtags" name="fixed_hashtags"
             value="#{Helpers.escape_attr(tags)}" placeholder="comma-separated">
      #{Helpers.error_message(errors, :fixed_hashtags)}
      <p class="help-text">
        Added to every published article as <code>t</code> tags.
        Duplicates of article hashtags are dropped.
      </p>
    </div>
    """
  end

  def excluded_hashtag_fields(params, source, errors) do
    tags =
      params["excluded_hashtags"] ||
        (source && Enum.join(source.excluded_hashtags || [], ", ")) ||
        ""

    tags =
      case tags do
        list when is_list(list) -> Enum.join(list, ", ")
        value -> to_string(value)
      end

    """
    <div class="form-group">
      <label for="excluded_hashtags">Excluded hashtags</label>
      <input type="text" id="excluded_hashtags" name="excluded_hashtags"
             value="#{Helpers.escape_attr(tags)}" placeholder="ROOT, Haupteintrag">
      #{Helpers.error_message(errors, :excluded_hashtags)}
      <p class="help-text">
        RSS categories on every item (for example <code>ROOT</code>, <code>Haupteintrag</code>)
        are dropped from published <code>t</code> tags.
      </p>
    </div>
    """
  end

  def staging_fields(params, source, errors) do
    hold =
      params["staging_hold_minutes"] ||
        (source && source.staging_hold_minutes) ||
        0

    notify =
      params["notify_pubkey"] || (source && source.notify_pubkey) || ""

    """
    <fieldset class="compose-fieldset">
      <legend>Staging</legend>
      <div class="form-group">
        <label for="staging_hold_minutes">Hold before auto-publish (minutes)</label>
        <input type="number" id="staging_hold_minutes" name="staging_hold_minutes" min="0" step="1"
               value="#{Helpers.escape_attr(to_string(hold))}">
        #{Helpers.error_message(errors, :staging_hold_minutes)}
        <p class="help-text">
          After an article enters staging, automated export waits this long.
          0 publishes on the next scheduler run. Manual Publish ignores the hold.
          Setup sources never auto-publish.
        </p>
      </div>
      <div class="form-group">
        <label for="notify_pubkey">Notify pubkey</label>
        <input type="text" id="notify_pubkey" name="notify_pubkey" placeholder="npub1… or hex"
               value="#{Helpers.escape_attr(notify)}" autocomplete="off">
        #{Helpers.error_message(errors, :notify_pubkey)}
        <p class="help-text">
          Optional. Receives a NIP-17 DM when an article first enters staging or is revised.
          Delivered to the recipient’s NIP-05 relays (or the public list if none are advertised),
          plus any extra relays in <code>NOSTR_RELAYS_INBOX</code>.
        </p>
      </div>
    </fieldset>
    """
  end

  def publish_as_fields(params, source, errors) do
    publish_as = params["publish_as"] || (source && source.publish_as) || "draft"
    draft_checked = if publish_as == "draft", do: "checked", else: ""
    plain_checked = if publish_as == "draft_plain", do: "checked", else: ""
    article_checked = if publish_as == "article", do: "checked", else: ""
    video_checked = if publish_as == "video", do: "checked", else: ""
    draft_hidden = if publish_as in ["draft", "draft_plain"], do: "", else: "hidden"
    article_hidden = if publish_as in ["article", "video"], do: "", else: "hidden"
    video_hidden = if publish_as == "video", do: "", else: "hidden"
    mirror_media = params["mirror_media"] || Helpers.option(source, "mirror_media") || "blossom"
    blossom_checked = if mirror_media != "original", do: "checked", else: ""
    original_checked = if mirror_media == "original", do: "checked", else: ""
    nsec_set? = source && Signer.signing_nsec_configured?(source)
    bunker = params["bunker_connection"] || (source && source.bunker_connection) || ""
    pubkey = params["pubkey"] || (source && source.pubkey) || ""

    """
    <fieldset class="compose-fieldset">
      <legend>Publish as</legend>
      <div class="choice-list">
        <label class="choice">
          <input type="radio" name="publish_as" value="draft" #{draft_checked}>
          <span>
            <strong>Draft (encrypted, NIP-37)</strong>
            <span class="help-text">Signed by the app key and NIP-44-encrypted into a kind 31234 wrap. The author’s pubkey is a <code>p</code> tag.</span>
          </span>
        </label>
        <label class="choice">
          <input type="radio" name="publish_as" value="draft_plain" #{plain_checked}>
          <span>
            <strong>Draft (unencrypted)</strong>
            <span class="help-text">A kind 30024 event signed by the app key. The author’s pubkey is a <code>p</code> tag.</span>
          </span>
        </label>
        <label class="choice">
          <input type="radio" name="publish_as" value="article" #{article_checked}>
          <span>
            <strong>Article (kind 30023)</strong>
            <span class="help-text">Signed by a source nsec or bunker URL as the author.</span>
          </span>
        </label>
        <label class="choice">
          <input type="radio" name="publish_as" value="video" #{video_checked}>
          <span>
            <strong>Video (kind 34235)</strong>
            <span class="help-text">NIP-71 addressable video. Imports enclosure-only feeds (no article page). Signed like an article.</span>
          </span>
        </label>
      </div>
      <p class="help-text">
        Drafts are sent to the draft relay list. Articles and videos are sent
        to the public relay list. Setup vs automated only controls whether the
        scheduler publishes on its own.
      </p>
    </fieldset>
    <div id="video-hosting-fields" #{video_hidden}>
      <fieldset class="compose-fieldset">
        <legend>Video file</legend>
        <div class="choice-list">
          <label class="choice">
            <input type="radio" name="mirror_media" value="blossom" #{blossom_checked}>
            <span>
              <strong>Mirror to Blossom</strong>
              <span class="help-text">Upload the MP4 to <code>NOSTR_UPLOAD_ENDPOINT</code> and put that URL on the event.</span>
            </span>
          </label>
          <label class="choice">
            <input type="radio" name="mirror_media" value="original" #{original_checked}>
            <span>
              <strong>Link original URL</strong>
              <span class="help-text">Leave the feed enclosure URL as-is. No download or upload.</span>
            </span>
          </label>
        </div>
      </fieldset>
    </div>
    <div id="draft-author-fields" #{draft_hidden}>
      <div class="form-group">
        <label for="pubkey">Author public key</label>
        <input type="text" id="pubkey" name="pubkey" placeholder="npub1… or hex"
               value="#{Helpers.escape_attr(pubkey)}" autocomplete="off">
        #{Helpers.error_message(errors, :pubkey)}
        <p class="help-text">Required for drafts. Added as a <code>p</code> tag so the intended author is known.</p>
      </div>
    </div>
    <div id="article-signer-fields" #{article_hidden}>
      <div class="form-group">
        <label for="signing_nsec">Author private key (nsec)</label>
        <input type="password" id="signing_nsec" name="signing_nsec" autocomplete="new-password"
               placeholder="#{if nsec_set?, do: "Configured — paste a new key to replace", else: "nsec1…"}">
        #{Helpers.error_message(errors, :signing_nsec)}
        <p class="help-text">Required for articles and videos unless a bunker URL is set. Stored encrypted.</p>
      </div>
      <div class="form-group">
        <label for="bunker_connection">Bunker URL</label>
        <input type="text" id="bunker_connection" name="bunker_connection"
               placeholder="bunker://…?relay=wss://…"
               value="#{Helpers.escape_attr(bunker)}" autocomplete="off">
        <p class="help-text">
          Alternative to an nsec. Unattended publishing works only if the remote signer auto-approves requests.
        </p>
      </div>
    </div>
    #{Scripts.publish_as_script()}
    """
  end
end
