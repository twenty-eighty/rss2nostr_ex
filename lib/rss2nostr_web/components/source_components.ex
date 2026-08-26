defmodule Rss2NostrWeb.SourceComponents do
  @moduledoc false

  use Rss2NostrWeb, :html

  alias Rss2Nostr.Nostr.Signer
  alias Rss2Nostr.Posts.Post
  alias Rss2Nostr.Processing.Composer

  @spec tab_link(map()) :: Phoenix.LiveView.Rendered.t()
  def tab_link(assigns) do
    assigns =
      assign(
        assigns,
        :class,
        if(assigns.name == assigns.current, do: "source-tab is-active", else: "source-tab")
      )

    ~H"""
    <.link patch={source_path(@source, @name)} class={@class}>{@label}</.link>
    """
  end

  @spec mode_badge(map()) :: Phoenix.LiveView.Rendered.t()
  def mode_badge(%{source: %{mode: "automated"}} = assigns) do
    ~H"""
    <button
      type="button"
      class="badge badge-processed"
      title="Switch back to setup"
      phx-click="set_mode"
      phx-value-mode="setup"
    >
      Automated
    </button>
    """
  end

  def mode_badge(assigns) do
    if Signer.configured?(assigns.source) do
      ~H"""
      <button
        type="button"
        class="badge badge-test"
        title="Switch to automated publishing"
        phx-click="set_mode"
        phx-value-mode="automated"
      >
        Setup
      </button>
      """
    else
      ~H"""
      <.link
        patch={source_path(@source, "publishing")}
        class="badge badge-test"
        title="Configure a signing key on the Publishing tab, then switch to automated"
      >
        Setup
      </.link>
      """
    end
  end

  @spec feed_tab(map()) :: Phoenix.LiveView.Rendered.t()
  def feed_tab(assigns) do
    ~H"""
    <form phx-submit="save_feed" class="form form-wide">
      <div class="form-group">
        <label for="name">Name</label>
        <input type="text" id="name" name="name" required value={@feed["name"]} />
        <.field_error field={:name} errors={@errors} />
      </div>
      <div class="form-group">
        <label for="url">Feed URL</label>
        <input
          type="text"
          id="url"
          name="url"
          required
          inputmode="url"
          autocomplete="url"
          value={@feed["url"]}
        />
        <.field_error field={:url} errors={@errors} />
        <p class="help-text">
          One RSS or Atom URL per source. Duplicate the source to follow another
          feed from the same site, then change this URL.
        </p>
      </div>
      <div class="form-group">
        <label for="language">Language</label>
        <select id="language" name="language">
          <option
            :for={{code, label} <- language_options(@feed["language"])}
            value={code}
            selected={code == @feed["language"]}
          >
            {label}
          </option>
        </select>
      </div>
      <div class="form-group">
        <label for="start_article">Start import from</label>
        <input
          type="hidden"
          id="start_published_at"
          name="start_published_at"
          value={@feed["start_published_at"]}
        />
        <select id="start_article" name="start_guid" phx-change="save_feed_start">
          <%= if @feed_items == :not_loaded do %>
            <option value="">Loading articles…</option>
          <% else %>
            <option value="">Beginning of the feed</option>
            <option
              :for={item <- @feed_items}
              value={item.guid}
              selected={item.guid == @feed["start_guid"]}
            >
              {item.title || item.guid}
            </option>
          <% end %>
        </select>
        <p :if={@feed_status} class="error">{@feed_status}</p>
        <p class="help-text">
          Changing this only affects future imports. Already imported articles stay.
          Current start: {start_label(@source, @feed["start_guid"], @feed["start_published_at"])}
        </p>
      </div>
      <div class="form-actions">
        <button type="submit" class="btn btn-primary">Save feed settings</button>
      </div>
    </form>
    """
  end

  @spec compose_tab(map()) :: Phoenix.LiveView.Rendered.t()
  def compose_tab(assigns) do
    ~H"""
    <form
      id="compose-source-form"
      phx-change="compose_changed"
      phx-submit="save_compose"
      class="form form-wide form-compose"
    >
      <div class="form-group">
        <label for="preview_article">Preview article</label>
        <select id="preview_article" name="guid">
          <%= if @feed_items == :not_loaded do %>
            <option value="">Loading articles…</option>
          <% else %>
            <option value="">Pick an article</option>
            <option
              :for={item <- @feed_items}
              value={item.guid}
              selected={item.guid == @compose["guid"]}
            >
              {item.title || item.guid}
            </option>
          <% end %>
        </select>
        <p class="compose-original-article" data-original-article>
          <%= if link = selected_article_link(@feed_items, @compose["guid"]) do %>
            <a href={link} target="_blank" rel="noopener noreferrer">Open original article</a>
          <% else %>
            <span class="help-text">Open original article</span>
          <% end %>
        </p>
        <p :if={@feed_status} class="error">{@feed_status}</p>
        <p class="help-text">
          This only affects the preview. Import still starts from the article chosen on the Feed tab.
        </p>
      </div>

      <div class="compose-layout">
        <div>
          <fieldset class="compose-fieldset">
            <legend>Article text</legend>
            <div class="choice-list">
              <label class="choice">
                <input
                  type="radio"
                  name="fetch_source_from"
                  value="content"
                  checked={@compose["fetch_source_from"] == "content"}
                />
                <span>
                  <strong>Contained in the feed XML</strong>
                  <span class="help-text">Use content:encoded or the Atom content from the feed.</span>
                </span>
              </label>
              <label class="choice">
                <input
                  type="radio"
                  name="fetch_source_from"
                  value="fetch_from_url"
                  checked={@compose["fetch_source_from"] != "content"}
                />
                <span>
                  <strong>Fetch from the article website</strong>
                  <span class="help-text">Download the article page, then pick the block that is the article.</span>
                </span>
              </label>
            </div>
          </fieldset>

          <fieldset class="compose-fieldset">
            <legend>Hashtags</legend>
            <div class="form-group">
              <label for="excluded_hashtags">Excluded hashtags</label>
              <input
                type="text"
                id="excluded_hashtags"
                name="excluded_hashtags"
                value={@compose["excluded_hashtags"]}
                placeholder="ROOT, Haupteintrag"
                phx-debounce="400"
              />
              <p class="help-text">
                RSS categories on every item (for example <code>ROOT</code>, <code>Haupteintrag</code>)
                are dropped from published <code>t</code> tags.
              </p>
            </div>
          </fieldset>

          <details
            id="body-regions-details"
            class="compose-advanced"
            open={not known_body_schema?(@compose["body_selector"], @source)}
          >
            <summary>Which block is the article?</summary>
            <p class="help-text">
              Click the region that looks like the article body. Known sites such as
              Substack are preselected from the article URL.
            </p>
            <input type="hidden" id="body_selector" value={@compose["body_selector"]} />
            <div id="body-regions" class="body-regions">
              <%= if @preview && @preview.body_regions != [] do %>
                <button
                  :for={region <- @preview.body_regions}
                  type="button"
                  class={["body-region", region.selected && "is-selected"]}
                  phx-click="pick_region"
                  phx-value-selector={region.selector}
                >
                  <strong>
                    {region.label || "Region"}
                    <span :if={region.recommended} class="body-region-badge">Preselected for this site</span>
                  </strong>
                  <span class="help-text">{region.first_line || "(empty)"}</span>
                  <span class="help-text">{region.word_count || 0} words</span>
                </button>
              <% else %>
                <p class="help-text">Load an article to see candidate regions.</p>
              <% end %>
            </div>
          </details>

          <details class="compose-advanced">
            <summary>Start here</summary>
            <p class="help-text">
              Click the first line that should appear in the body. Everything before it is dropped.
            </p>
            <input type="hidden" id="start_at" value={@compose["start_at"]} />
            <div id="start-blocks" class="start-blocks">
              <button
                type="button"
                class={["start-block", @compose["start_at"] in [nil, ""] && "is-selected"]}
                phx-click="pick_start"
                phx-value-xpath=""
              >
                Beginning of the article
              </button>
              <%= if @preview do %>
                <button
                  :for={block <- @preview.start_blocks}
                  type="button"
                  class={["start-block", block.selected && "is-selected"]}
                  phx-click="pick_start"
                  phx-value-xpath={block.xpath}
                >
                  {block.text}
                </button>
              <% else %>
                <p class="help-text">Load an article to see opening lines.</p>
              <% end %>
            </div>
          </details>

          <details class="compose-advanced">
            <summary>Technical settings</summary>
            <div class="form-group">
              <label for="body_preset">Body selector preset</label>
              <select id="body_preset" name="body_preset">
                <option
                  :for={{label, value} <- Composer.body_presets()}
                  value={value}
                  selected={value != "" and value == @compose["body_selector"]}
                >
                  {label}
                </option>
              </select>
            </div>
            <div class="form-group">
              <label for="body_selector_text">Body CSS selector</label>
              <input
                type="text"
                id="body_selector_text"
                name="body_selector"
                placeholder="article, div.entry-content, …"
                value={@compose["body_selector"]}
                autocomplete="off"
                phx-debounce="400"
              />
              <p class="help-text">Leave empty to convert the whole HTML.</p>
            </div>
            <div class="form-group">
              <label for="start_at_text">Start at (XPath)</label>
              <input
                type="text"
                id="start_at_text"
                name="start_at"
                value={@compose["start_at"]}
                autocomplete="off"
                phx-debounce="400"
              />
            </div>
            <div class="form-group">
              <label for="skip_classes">Skip these CSS classes</label>
              <textarea id="skip_classes" name="skip_classes" rows="3" phx-debounce="400">{@compose["skip_classes"]}</textarea>
              <p class="help-text">Comma-separated class names to drop (ads, comments, teasers).</p>
            </div>
          </details>
          <.field_error field={:body_selector} errors={@errors} />
          <div class="form-actions">
            <button type="submit" class="btn btn-primary">Save composition</button>
          </div>
        </div>

        <.compose_preview
          preview={@preview}
          preview_status={@preview_status}
          preview_tab={@preview_tab}
          show_split={@show_split}
        />
      </div>
    </form>
    """
  end

  @spec compose_preview(map()) :: Phoenix.LiveView.Rendered.t()
  def compose_preview(assigns) do
    parts = preview_parts(assigns.preview)
    assigns = assign(assigns, :parts, parts)

    ~H"""
    <div class="compose-preview-panel">
      <div class="compose-preview-header">
        <label>Nostr event preview</label>
        <div class="compose-preview-actions">
          <div class="compose-tabs" role="tablist">
            <button
              type="button"
              class={["compose-tab", @preview_tab == "rendered" && "is-active"]}
              data-preview-tab="rendered"
              phx-click="set_preview_tab"
              phx-value-tab="rendered"
            >
              Preview
            </button>
            <button
              type="button"
              class={["compose-tab", @preview_tab == "source" && "is-active"]}
              data-preview-tab="source"
              phx-click="set_preview_tab"
              phx-value-tab="source"
            >
              Markdown
            </button>
            <button
              type="button"
              class={["compose-tab", @preview_tab == "event" && "is-active"]}
              data-preview-tab="event"
              phx-click="set_preview_tab"
              phx-value-tab="event"
            >
              Event
            </button>
          </div>
          <label class="compose-split-toggle" id="compose-split-toggle" hidden={length(@parts) <= 1}>
            <input
              type="checkbox"
              id="show-split-parts"
              checked={@show_split}
              phx-click="toggle_split"
            /> Show split parts
          </label>
          <button type="button" class="btn btn-small btn-secondary" phx-click="refresh_preview">
            Refresh
          </button>
        </div>
      </div>
      <p class="help-text">
        {@preview_status || if(@preview, do: nil, else: "Pick an article to preview the Markdown.")}
      </p>
      <%= if preview = @preview do %>
        <div class="compose-preview-meta">
          <p><strong>Title:</strong> {preview.title || "—"}</p>
          <p :if={preview.summary}><strong>Summary:</strong> {preview.summary}</p>
          <p :if={preview.hashtags != []}>
            <strong>Hashtags:</strong> {Enum.join(preview.hashtags, ", ")}
          </p>
          <p :if={length(@parts) > 1}><strong>Parts:</strong> {length(@parts)} Nostr events</p>
          <p :if={preview.selector_matched == false}>
            <strong>Selector:</strong> Did not match; using the full HTML.
          </p>
        </div>
        <div :if={preview.image} class="compose-hero compose-preview-hero">
          <img src={preview.image} alt="" />
        </div>
        <article class="compose-preview-rendered" hidden={@preview_tab != "rendered"}>
          <%= if @show_split and @parts != [] do %>
            <section :for={part <- @parts} class="compose-preview-part">
              <p class="compose-preview-part-label">Part {part.index}/{part.total}</p>
              {raw(part.html || "")}
            </section>
          <% else %>
            {raw(preview.html || "")}
          <% end %>
        </article>
        <div class="compose-preview" hidden={@preview_tab != "source"}>
          <%= if @show_split and @parts != [] do %>
            <section :for={part <- @parts} class="compose-preview-part">
              <p class="compose-preview-part-label">Part {part.index}/{part.total}</p>
              <pre class="compose-preview-part-markdown">{part.markdown || "(empty)"}</pre>
            </section>
          <% else %>
            <pre>{preview.markdown || "(empty)"}</pre>
          <% end %>
        </div>
        <pre class="compose-preview compose-preview-event" hidden={@preview_tab != "event"}>
          {event_preview_text(preview)}
        </pre>
      <% else %>
        <div class="compose-preview-hero"></div>
        <article class="compose-preview-rendered" hidden={@preview_tab != "rendered"}></article>
        <pre class="compose-preview compose-preview-event" hidden={@preview_tab != "event"}></pre>
      <% end %>
    </div>
    """
  end

  @spec articles_tab(map()) :: Phoenix.LiveView.Rendered.t()
  def articles_tab(assigns) do
    selectable? = Enum.any?(assigns.posts, &reprocessable?/1)
    selected = assigns.selected_ids
    publishable_selected? = Enum.any?(assigns.posts, &(&1.id in selected and publishable?(&1)))

    reprocess_selected? =
      Enum.any?(selected, fn id -> Enum.any?(assigns.posts, &(&1.id == id)) end)

    all_selected? =
      selectable? and
        Enum.all?(Enum.filter(assigns.posts, &reprocessable?/1), &(&1.id in selected))

    assigns =
      assigns
      |> assign(:selectable?, selectable?)
      |> assign(:publishable_selected?, publishable_selected?)
      |> assign(:reprocess_selected?, reprocess_selected?)
      |> assign(:all_selected?, all_selected?)
      |> assign(:relay_label, relay_target_name(target_for(assigns.source)))

    ~H"""
    <div class="article-toolbar">
      <button type="button" class="btn btn-secondary" phx-click="import" disabled={@busy}>
        Import now
      </button>
      <button
        type="button"
        class="btn btn-primary"
        phx-click="publish_selected"
        disabled={@busy or not @publishable_selected?}
      >
        Publish selected
      </button>
      <button
        type="button"
        class="btn btn-secondary"
        phx-click="reprocess_selected"
        disabled={@busy or not @reprocess_selected?}
      >
        Reprocess selected
      </button>
      <span class="article-selection-count">
        {MapSet.size(@selected_ids)} selected
      </span>
    </div>
    <p class="help-text">
      Selected staging articles publish to the {@relay_label}. Setup never uses the public list.
      Pending-images and error articles can be reprocessed; pending articles stay pending until featured and inline images are uploaded.
      Manual publish ignores the staging hold.
    </p>
    <table class="table">
      <thead>
        <tr>
          <th class="article-select">
            <input
              type="checkbox"
              id="select-all-articles"
              aria-label="Select all articles"
              phx-click="toggle_all"
              phx-value-checked={to_string(not @all_selected?)}
              checked={@all_selected?}
              disabled={not @selectable?}
            />
          </th>
          <th>Title</th>
          <th>Status</th>
          <th>Published</th>
          <th></th>
        </tr>
      </thead>
      <tbody>
        <%= if @posts == [] do %>
          <tr>
            <td colspan="5" class="empty-state">No articles imported yet.</td>
          </tr>
        <% else %>
          <tr :for={post <- @posts} id={"article-#{post.id}"}>
            <td class="article-select">
              <input
                :if={reprocessable?(post)}
                type="checkbox"
                name="post_ids[]"
                value={post.id}
                data-publishable={to_string(publishable?(post))}
                checked={MapSet.member?(@selected_ids, post.id)}
                phx-click="toggle_post"
                phx-value-id={post.id}
              />
            </td>
            <td>
              <a href={post_preview_href(@source, post)}>{truncate(post.title, 70)}</a>
            </td>
            <td class="article-status"><.status_badge status={post.status} /></td>
            <td>{format_datetime(post.published_at)}</td>
            <td class="actions">
              <a href={post_preview_href(@source, post)} class="btn btn-small">Preview</a>
              <button
                :if={post.status == Post.status_pending_images()}
                type="button"
                class="btn btn-small"
                phx-click="upload_images"
                phx-value-id={post.id}
                disabled={@busy}
              >
                Upload images
              </button>
              <button
                :if={post.status == Post.status_error()}
                type="button"
                class="btn btn-small"
                phx-click="reprocess_post"
                phx-value-id={post.id}
                disabled={@busy}
              >
                Retry
              </button>
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
    """
  end

  @spec publishing_tab(map()) :: Phoenix.LiveView.Rendered.t()
  def publishing_tab(assigns) do
    publish_as = assigns.publishing["publish_as"]
    signer_ok? = Signer.configured?(assigns.source)

    assigns =
      assigns
      |> assign(:publish_as, publish_as)
      |> assign(:draft?, publish_as in ["draft", "draft_plain"])
      |> assign(:article?, publish_as in ["article", "video"])
      |> assign(:video?, publish_as == "video")
      |> assign(:signer_ok?, signer_ok?)
      |> assign(:nsec_set?, Signer.signing_nsec_configured?(assigns.source))

    ~H"""
    <form phx-change="publishing_changed" phx-submit="save_publishing" class="form form-wide">
      <fieldset class="compose-fieldset">
        <legend>Publish as</legend>
        <div class="choice-list">
          <label class="choice">
            <input type="radio" name="publish_as" value="draft" checked={@publish_as == "draft"} />
            <span>
              <strong>Draft (encrypted, NIP-37)</strong>
              <span class="help-text">Signed by the app key and NIP-44-encrypted into a kind 31234 wrap. The author’s pubkey is a
              <code>p</code>
              tag.</span>
            </span>
          </label>
          <label class="choice">
            <input
              type="radio"
              name="publish_as"
              value="draft_plain"
              checked={@publish_as == "draft_plain"}
            />
            <span>
              <strong>Draft (unencrypted)</strong>
              <span class="help-text">A kind 30024 event signed by the app key. The author’s pubkey is a
              <code>p</code>
              tag.</span>
            </span>
          </label>
          <label class="choice">
            <input type="radio" name="publish_as" value="article" checked={@publish_as == "article"} />
            <span>
              <strong>Article (kind 30023)</strong>
              <span class="help-text">Signed by a source nsec or bunker URL as the author.</span>
            </span>
          </label>
          <label class="choice">
            <input type="radio" name="publish_as" value="video" checked={@publish_as == "video"} />
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

      <div id="video-hosting-fields" hidden={not @video?}>
        <fieldset class="compose-fieldset">
          <legend>Video file</legend>
          <div class="choice-list">
            <label class="choice">
              <input
                type="radio"
                name="mirror_media"
                value="blossom"
                checked={@publishing["mirror_media"] != "original"}
              />
              <span>
                <strong>Mirror to Blossom</strong>
                <span class="help-text">Upload the MP4 to <code>NOSTR_UPLOAD_ENDPOINT</code>
                and put that URL on the event.</span>
              </span>
            </label>
            <label class="choice">
              <input
                type="radio"
                name="mirror_media"
                value="original"
                checked={@publishing["mirror_media"] == "original"}
              />
              <span>
                <strong>Link original URL</strong>
                <span class="help-text">Leave the feed enclosure URL as-is. No download or upload.</span>
              </span>
            </label>
          </div>
        </fieldset>
      </div>

      <div id="draft-author-fields" hidden={not @draft?}>
        <div class="form-group">
          <label for="pubkey">Author public key</label>
          <input
            type="text"
            id="pubkey"
            name="pubkey"
            placeholder="npub1… or hex"
            value={@publishing["pubkey"]}
            autocomplete="off"
          />
          <.field_error field={:pubkey} errors={@errors} />
          <p class="help-text">
            Required for drafts. Added as a <code>p</code> tag so the intended author is known.
          </p>
        </div>
      </div>

      <div id="article-signer-fields" hidden={not @article?}>
        <div class="form-group">
          <label for="signing_nsec">Author private key (nsec)</label>
          <input
            type="password"
            id="signing_nsec"
            name="signing_nsec"
            autocomplete="new-password"
            placeholder={if @nsec_set?, do: "Configured — paste a new key to replace", else: "nsec1…"}
          />
          <.field_error field={:signing_nsec} errors={@errors} />
          <p class="help-text">
            Required for articles and videos unless a bunker URL is set. Stored encrypted.
          </p>
        </div>
        <div class="form-group">
          <label for="bunker_connection">Bunker URL</label>
          <input
            type="text"
            id="bunker_connection"
            name="bunker_connection"
            placeholder="bunker://…?relay=wss://…"
            value={@publishing["bunker_connection"]}
            autocomplete="off"
          />
          <p class="help-text">
            Alternative to an nsec. Unattended publishing works only if the remote signer auto-approves requests.
          </p>
        </div>
      </div>

      <div class="form-group">
        <label for="fixed_hashtags">Fixed hashtags</label>
        <input
          type="text"
          id="fixed_hashtags"
          name="fixed_hashtags"
          value={@publishing["fixed_hashtags"]}
          placeholder="comma-separated"
        />
        <.field_error field={:fixed_hashtags} errors={@errors} />
        <p class="help-text">
          Added to every published article as <code>t</code> tags.
          Duplicates of article hashtags are dropped.
        </p>
      </div>

      <div class="form-group">
        <label for="excluded_hashtags">Excluded hashtags</label>
        <input
          type="text"
          id="excluded_hashtags"
          name="excluded_hashtags"
          value={@publishing["excluded_hashtags"]}
          placeholder="ROOT, Haupteintrag"
        />
        <.field_error field={:excluded_hashtags} errors={@errors} />
        <p class="help-text">
          RSS categories on every item (for example <code>ROOT</code>, <code>Haupteintrag</code>)
          are dropped from published <code>t</code> tags.
        </p>
      </div>

      <fieldset class="compose-fieldset">
        <legend>Staging</legend>
        <div class="form-group">
          <label for="staging_hold_minutes">Hold before auto-publish (minutes)</label>
          <input
            type="number"
            id="staging_hold_minutes"
            name="staging_hold_minutes"
            min="0"
            step="1"
            value={@publishing["staging_hold_minutes"]}
          />
          <.field_error field={:staging_hold_minutes} errors={@errors} />
          <p class="help-text">
            After an article enters staging, automated export waits this long.
            0 publishes on the next scheduler run. Manual Publish ignores the hold.
            Setup sources never auto-publish.
          </p>
        </div>
        <div class="form-group">
          <label for="notify_pubkey">Notify pubkey</label>
          <input
            type="text"
            id="notify_pubkey"
            name="notify_pubkey"
            placeholder="npub1… or hex"
            value={@publishing["notify_pubkey"]}
            autocomplete="off"
          />
          <.field_error field={:notify_pubkey} errors={@errors} />
          <p class="help-text">
            Optional. Receives a NIP-17 DM when an article first enters staging or is revised.
            Delivered to the recipient’s NIP-05 relays (or the public list if none are advertised),
            plus any extra relays in <code>NOSTR_RELAYS_INBOX</code>.
          </p>
        </div>
      </fieldset>

      <.field_error field={:mode} errors={@errors} />
      <%= if @signer_ok? do %>
        <p class="help-text">
          Use the Setup / Automated badge at the top of the page to change mode.
        </p>
      <% else %>
        <p class="help-text">
          Configure a signing key before switching to automated publishing. Use the Setup badge at the top once a key is set.
        </p>
      <% end %>
      <div class="form-actions">
        <button type="submit" class="btn btn-primary">Save publishing settings</button>
      </div>
    </form>
    """
  end

  @spec selected_article_link(term(), term()) :: String.t() | nil
  defp selected_article_link(:not_loaded, _), do: nil

  defp selected_article_link(items, guid) when is_list(items) do
    case Enum.find(items, &(&1.guid == guid)) do
      %{link: link} when is_binary(link) and link != "" -> link
      _ -> nil
    end
  end

  defp selected_article_link(_, _), do: nil

  @spec preview_parts(map() | nil) :: list()
  defp preview_parts(nil), do: []
  defp preview_parts(%{nostr_parts_preview: parts}) when is_list(parts), do: parts
  defp preview_parts(_), do: []

  @spec event_preview_text(map()) :: String.t()
  defp event_preview_text(preview) do
    relays = Enum.join(preview.nostr_relays || [], "\n")
    parts = preview.nostr_parts_json || []
    intro = if relays != "", do: "Relays:\n#{relays}\n\n", else: ""

    intro <> split_note(preview, parts) <> event_preview_body(preview, parts)
  end

  @spec split_note(map(), list()) :: String.t()
  defp split_note(preview, parts) do
    cond do
      preview.nostr_draft and length(parts) > 1 ->
        "This article will be published as #{length(parts)} NIP-37 drafts so each published wrap stays within 65535 bytes.\n\n"

      preview.nostr_draft ->
        "This inner article is NIP-44-encrypted into a kind 31234 wrap when published.\n\n"

      preview.nostr_plain_draft ->
        "Published as kind 30024, signed by the app key.\n\n"

      true ->
        ""
    end
  end

  @spec event_preview_body(map(), list()) :: String.t()
  defp event_preview_body(preview, []), do: preview.nostr_event_json || "{}"

  defp event_preview_body(_preview, list) do
    total = length(list)

    list
    |> Enum.with_index(1)
    |> Enum.map_join("\n\n", fn {json, i} -> part_prefix(total, i) <> json end)
  end

  @spec part_prefix(integer(), integer()) :: String.t()
  defp part_prefix(total, i) when total > 1, do: "Part #{i}/#{total}:\n"
  defp part_prefix(_total, _i), do: ""
end
