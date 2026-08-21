defmodule Rss2Nostr.Web.Views.Sources do
  @moduledoc """
  Views for source management.
  """

  alias Rss2Nostr.Web.Views.Layout
  alias Rss2Nostr.Sources
  alias Rss2Nostr.Sources.Source
  alias Rss2Nostr.Posts
  alias Rss2Nostr.Posts.Post
  alias Rss2Nostr.Processing.{BodySchema, Composer}
  alias Rss2Nostr.Nostr.{Relays, Signer}

  def index do
    sources = Sources.list_sources()

    rows =
      if Enum.empty?(sources) do
        """
        <tr>
          <td colspan="7" class="empty-state">No sources configured. <a href="/sources/new">Add one</a>.</td>
        </tr>
        """
      else
        Enum.map_join(sources, "", fn source ->
          """
          <tr>
            <td>#{source_name_cell(source)}</td>
            <td><code class="url">#{escape_html(truncate(source.url, 50))}</code></td>
            <td>#{source.type}</td>
            <td>
              <span class="badge #{if source.mode == "automated", do: "badge-processed", else: "badge-test"}">
                #{if source.mode == "automated", do: "Automated", else: "Setup"}
              </span>
            </td>
            <td>
              <span class="badge #{relay_badge_class(Relays.target_for(source))}">
                #{relay_target_label(Relays.target_for(source))}
              </span>
            </td>
            <td>
              <span class="badge #{if source.active, do: "badge-active", else: "badge-inactive"}">
                #{if source.active, do: "Active", else: "Inactive"}
              </span>
            </td>
            <td class="actions">
              <a href="/sources/#{source.id}" class="btn btn-small">Open</a>
              <form action="/sources/#{source.id}/duplicate" method="POST" style="display:inline">
                <button type="submit" class="btn btn-small">Duplicate</button>
              </form>
              <form action="/sources/#{source.id}/toggle" method="POST" style="display:inline">
                <button type="submit" class="btn btn-small">
                  #{if source.active, do: "Disable", else: "Enable"}
                </button>
              </form>
              <form action="/sources/#{source.id}/delete" method="POST" style="display:inline"
                    onsubmit="return confirm('Delete this source and all of its articles?')">
                <button type="submit" class="btn btn-small btn-danger">Delete</button>
              </form>
            </td>
          </tr>
          """
        end)
      end

    content = """
    <div class="page-header">
      <h1>Sources</h1>
      <a href="/sources/new" class="btn btn-primary">Add Source</a>
    </div>

    <table class="table" id="sources-table" data-relays="#{escape_attr(avatar_relays())}">
      <thead>
        <tr>
          <th>Name</th>
          <th>URL</th>
          <th>Type</th>
          <th>Mode</th>
          <th>Relays</th>
          <th>Status</th>
          <th>Actions</th>
        </tr>
      </thead>
      <tbody>
        #{rows}
      </tbody>
    </table>
    #{source_avatar_script()}
    """

    Layout.render("Sources", content, active_nav: "sources")
  end

  def new(opts \\ []) do
    errors = Keyword.get(opts, :errors, %{})
    params = Keyword.get(opts, :params, %{})

    content = """
    <h1>Add Source</h1>

    <form action="/sources" method="POST" class="form form-wide form-compose" id="add-source-form">
      <div class="form-group">
        <label for="website">Website or feed URL</label>
        <div class="input-row">
          <input type="text" id="website" name="website" required
                 inputmode="url" autocomplete="url"
                 placeholder="https://example.com or https://example.com/feed.xml"
                 value="#{escape_attr(params["website"])}">
          <button type="button" class="btn btn-secondary" id="discover-button">Find feeds</button>
        </div>
        <p class="help-text">Paste a website to discover its feeds, or paste an RSS/Atom URL directly.</p>
        <p id="discover-status" class="help-text"></p>
        <p id="discover-error" class="error" hidden></p>
      </div>

      <div id="source-details" #{if params["url"] in [nil, ""], do: "hidden", else: ""}>
        <div class="form-group" id="feeds-group">
          <label>Feeds</label>
          <div id="feeds-list" class="choice-list"></div>
          #{error_message(errors, :url)}
        </div>

        <input type="hidden" id="url" name="url" value="#{escape_attr(params["url"])}">
        <input type="hidden" id="type" name="type" value="#{escape_attr(params["type"] || "atom")}">
        <input type="hidden" id="start_guid" name="start_guid" value="#{escape_attr(params["start_guid"])}">
        <input type="hidden" id="start_published_at" name="start_published_at" value="#{escape_attr(params["start_published_at"])}">

        <div class="form-group">
          <label for="name">Name</label>
          <input type="text" id="name" name="name" required placeholder="e.g., Heise News"
                 value="#{escape_attr(params["name"])}">
          #{error_message(errors, :name)}
        </div>

        <div class="form-group">
          <label for="start_article">Start import from</label>
          <select id="start_article">
            <option value="">Loading articles…</option>
          </select>
          <p class="help-text">Articles older than this one are skipped. Newer items in later fetches are still imported.</p>
        </div>

        <div class="form-group">
          <label for="language">Language</label>
          #{language_select(params["language"] || "de")}
        </div>

        #{publish_as_fields(params, nil, errors)}
        #{fixed_hashtag_fields(params, nil, errors)}
      </div>

      <div class="form-actions">
        <button type="submit" class="btn btn-primary" id="submit-source" #{if params["url"] in [nil, ""], do: "disabled", else: ""}>Add Source</button>
        <a href="/sources" class="btn btn-secondary">Cancel</a>
      </div>
    </form>
    #{discover_script()}
    """

    Layout.render("Add Source", content, active_nav: "sources", wide: true)
  end

  def compose(source, opts \\ []), do: show(source, opts)

  def show(source, opts \\ []) do
    tab = normalize_tab(Keyword.get(opts, :tab, "compose"))
    errors = Keyword.get(opts, :errors, %{})
    params = Keyword.get(opts, :params, %{})
    saved? = Keyword.get(opts, :saved, false)
    notice = Keyword.get(opts, :notice)
    notice_kind = Keyword.get(opts, :notice_kind)
    target = Relays.target_for(source)

    content = """
    <div class="page-header">
      <h1>#{escape_html(source.name)}</h1>
      <div>
        #{mode_badge(source, tab)}
        <span class="badge #{if target == :public, do: "badge-public", else: "badge-test"}">
          #{relay_target_label(target)}
        </span>
        <form action="/sources/#{source.id}/duplicate" method="POST" style="display:inline">
          <button type="submit" class="btn btn-secondary">Duplicate</button>
        </form>
        <a href="/sources" class="btn btn-secondary">Back to sources</a>
      </div>
    </div>

    #{if saved?, do: "<p class=\"success\">Settings saved.</p>", else: ""}
    #{flash_notice(notice, notice_kind)}

    <nav class="source-tabs" aria-label="Source sections">
      #{tab_link(source, "feed", "Feed", tab)}
      #{tab_link(source, "compose", "Compose", tab)}
      #{tab_link(source, "articles", "Articles", tab)}
      #{tab_link(source, "publishing", "Publishing", tab)}
    </nav>

    #{tab_content(source, tab, params, errors)}
    """

    Layout.render(source.name, content, active_nav: "sources", wide: tab == "compose")
  end

  defp normalize_tab(tab) when tab in ["feed", "compose", "articles", "publishing"], do: tab
  defp normalize_tab(_), do: "compose"

  defp tab_link(source, name, label, current) do
    class = if name == current, do: "source-tab is-active", else: "source-tab"
    ~s(<a class="#{class}" href="/sources/#{source.id}?tab=#{name}">#{label}</a>)
  end

  defp tab_content(source, "feed", params, errors), do: feed_tab(source, params, errors)
  defp tab_content(source, "compose", params, errors), do: compose_tab(source, params, errors)
  defp tab_content(source, "articles", _params, _errors), do: articles_tab(source)

  defp tab_content(source, "publishing", params, errors),
    do: publishing_tab(source, params, errors)

  defp feed_tab(source, params, errors) do
    start_guid = params["start_guid"] || option(source, "start_guid") || ""
    start_at = params["start_published_at"] || datetime_value(source.publish_after_date)

    """
    <form action="/sources/#{source.id}" method="POST" class="form form-wide">
      <input type="hidden" name="tab" value="feed">
      <div class="form-group">
        <label for="name">Name</label>
        <input type="text" id="name" name="name" required
               value="#{escape_attr(params["name"] || source.name)}">
        #{error_message(errors, :name)}
      </div>
      <div class="form-group">
        <label for="url">Feed URL</label>
        <input type="text" id="url" name="url" required inputmode="url" autocomplete="url"
               value="#{escape_attr(params["url"] || source.url)}">
        #{error_message(errors, :url)}
        <p class="help-text">
          One RSS or Atom URL per source. Duplicate the source to follow another
          feed from the same site, then change this URL.
        </p>
      </div>
      <div class="form-group">
        <label for="language">Language</label>
        #{language_select(params["language"] || source.language || "de")}
      </div>
      <div class="form-group">
        <label for="start_article">Start import from</label>
        <input type="hidden" id="start_guid" name="start_guid" value="#{escape_attr(to_string(start_guid))}">
        <input type="hidden" id="start_published_at" name="start_published_at" value="#{escape_attr(start_at)}">
        <select id="start_article">
          <option value="">Loading articles…</option>
        </select>
        <p class="help-text">
          Changing this only affects future imports. Already imported articles stay.
          Current start: #{escape_html(start_label(source, start_guid, start_at))}
        </p>
      </div>
      <div class="form-group checkbox">
        <input type="hidden" name="public" value="false">
        <label for="public">
          <input type="checkbox" id="public" name="public" value="true"
                 #{if public_checked?(params, source), do: "checked", else: ""}>
          Intended for public relays
        </label>
        <p class="help-text">
          Articles use the public relay list when this is checked, otherwise
          the test list. Drafts always use the draft list. Setup vs automated
          only controls whether the scheduler publishes on its own.
        </p>
      </div>
      <div class="form-actions">
        <button type="submit" class="btn btn-primary">Save feed settings</button>
      </div>
    </form>
    #{feed_start_script()}
    """
  end

  defp compose_tab(source, params, errors) do
    """
    <form action="/sources/#{source.id}" method="POST" class="form form-wide form-compose" id="compose-source-form">
      <input type="hidden" name="tab" value="compose">
      <input type="hidden" id="source_id" name="source_id" value="#{source.id}">
      <input type="hidden" id="url" name="url" value="#{escape_attr(source.url)}">
      <input type="hidden" id="type" name="type" value="#{escape_attr(source.type)}">
      <div class="form-group">
        <label for="preview_article">Preview article</label>
        <select id="preview_article">
          <option value="">Loading articles…</option>
        </select>
        <p class="compose-original-article" data-original-article hidden>
          <a target="_blank" rel="noopener noreferrer">Open original article</a>
        </p>
        <p class="help-text">This only affects the preview. Import still starts from the article chosen on the Feed tab.</p>
      </div>
      #{compose_layout(params, source)}
      #{error_message(errors, :body_selector)}
      <div class="form-actions">
        <button type="submit" class="btn btn-primary">Save composition</button>
      </div>
    </form>
    #{compose_page_script()}
    #{compose_script()}
    """
  end

  defp articles_tab(source) do
    posts = Posts.list_posts_for_source(source.id, limit: 100)
    relay_label = relay_target_name(Relays.target_for(source))
    selectable? = Enum.any?(posts, &(&1.status == Post.status_processed()))

    rows =
      if Enum.empty?(posts) do
        "<tr><td colspan=\"5\" class=\"empty-state\">No articles imported yet.</td></tr>"
      else
        Enum.map_join(posts, "", fn post ->
          """
          <tr id="article-#{post.id}">
            <td class="article-select">
              #{if post.status == Post.status_processed() do
            ~s(<input type="checkbox" name="post_ids[]" value="#{post.id}">)
          else
            ""
          end}
            </td>
            <td><a href="/posts/#{post.id}">#{escape_html(truncate(post.title, 70))}</a></td>
            <td class="article-status"><span class="badge #{status_class(post.status)}">#{Post.status_label(post.status)}</span></td>
            <td>#{format_datetime(post.published_at)}</td>
            <td class="actions">
              <a href="/posts/#{post.id}" class="btn btn-small">Preview</a>
              #{if post.status == Post.status_pending_images() do
            ~s(<button type="submit" class="btn btn-small js-upload-images" form="upload-post-#{post.id}">Upload images</button>)
          end}
            </td>
          </tr>
          """
        end)
      end

    """
    <div class="article-toolbar">
      <form action="/sources/#{source.id}/import" method="POST">
        <button type="submit" class="btn btn-secondary">Import now</button>
      </form>
      <button type="submit" class="btn btn-primary js-articles-bulk" form="articles-bulk-form" disabled>Publish selected</button>
      <button type="submit" class="btn btn-secondary js-articles-bulk" form="articles-bulk-form"
              formaction="/sources/#{source.id}/reprocess-selected" disabled>Reprocess selected</button>
    </div>
    <p class="help-text">Selected staging articles publish to the #{relay_label}. Setup never uses the public list. Articles stay in pending images until featured and inline images are uploaded. Manual publish ignores the staging hold.</p>
    #{upload_forms(source, posts)}
    <form id="articles-bulk-form" action="/sources/#{source.id}/publish-selected" method="POST">
      <table class="table">
        <thead>
          <tr>
            <th class="article-select">
              <input type="checkbox" id="select-all-articles" aria-label="Select all staging articles"
                     #{unless selectable?, do: "disabled"}>
            </th>
            <th>Title</th>
            <th>Status</th>
            <th>Published</th>
            <th></th>
          </tr>
        </thead>
        <tbody>#{rows}</tbody>
      </table>
    </form>
    #{articles_upload_script()}
    """
  end

  defp upload_forms(source, posts) do
    return_to = "/sources/#{source.id}?tab=articles"

    posts
    |> Enum.filter(&(&1.status == Post.status_pending_images()))
    |> Enum.map_join("", fn post ->
      """
      <form id="upload-post-#{post.id}" action="/posts/#{post.id}/process" method="POST" hidden>
        <input type="hidden" name="return_to" value="#{escape_attr(return_to)}">
      </form>
      """
    end)
  end

  defp articles_upload_script do
    """
    <script>
    (function () {
      const selectAll = document.getElementById("select-all-articles");

      function selectableBoxes() {
        return document.querySelectorAll("#articles-bulk-form input[name='post_ids[]']");
      }

      function syncSelectAll() {
        const boxes = Array.from(selectableBoxes());
        const checked = boxes.filter(function (box) { return box.checked; }).length;
        if (selectAll) {
          selectAll.disabled = boxes.length === 0;
          selectAll.checked = boxes.length > 0 && checked === boxes.length;
          selectAll.indeterminate = checked > 0 && checked < boxes.length;
        }
        document.querySelectorAll(".js-articles-bulk").forEach(function (button) {
          button.disabled = checked === 0;
        });
      }

      if (selectAll) {
        selectAll.addEventListener("change", function () {
          selectableBoxes().forEach(function (box) {
            box.checked = selectAll.checked;
          });
          selectAll.indeterminate = false;
          syncSelectAll();
        });
        document.addEventListener("change", function (event) {
          if (event.target && event.target.name === "post_ids[]") syncSelectAll();
        });
      }

      syncSelectAll();

      function statusClass(status) {
        switch (status) {
          case 0: return "badge-new";
          case 1: return "badge-processing";
          case 2: return "badge-processed";
          case 6: return "badge-published";
          case 9: return "badge-pending-images";
          default: return "badge-error";
        }
      }

      function updateRow(row, body) {
        const statusCell = row.querySelector(".article-status");
        if (statusCell) {
          const badge = document.createElement("span");
          badge.className = "badge " + statusClass(body.status);
          badge.textContent = body.status_label || body.status_name || "";
          if (body.last_error) badge.title = body.last_error;
          statusCell.replaceChildren(badge);
        }

        const select = row.querySelector(".article-select");
        const upload = row.querySelector(".js-upload-images");

        if (body.selectable) {
          if (select && !select.querySelector("input")) {
            const box = document.createElement("input");
            box.type = "checkbox";
            box.name = "post_ids[]";
            box.value = String(body.id);
            select.replaceChildren(box);
          }
          if (upload) upload.remove();
          syncSelectAll();
        } else if (upload) {
          upload.disabled = false;
          upload.textContent = "Upload images";
          if (body.last_error) upload.title = body.last_error;
        }
      }

      document.querySelectorAll(".js-upload-images").forEach(function (button) {
        button.addEventListener("click", async function (event) {
          event.preventDefault();
          const form = document.getElementById(button.getAttribute("form"));
          if (!form) return;

          const row = button.closest("tr");
          button.disabled = true;
          button.textContent = "Uploading…";

          try {
            const res = await fetch(form.action, {
              method: "POST",
              headers: { Accept: "application/json" },
              body: new FormData(form),
              credentials: "same-origin"
            });
            const body = await res.json();
            if (!res.ok) throw new Error(body.error || "Upload failed");
            if (row) updateRow(row, body);
          } catch (err) {
            button.disabled = false;
            button.textContent = "Upload images";
            button.title = err.message || "Upload failed";
          }
        });
      });
    })();
    </script>
    """
  end

  defp publishing_tab(source, params, errors) do
    signer_ok? = Signer.configured?(source)

    """
    <form action="/sources/#{source.id}" method="POST" class="form form-wide">
      <input type="hidden" name="tab" value="publishing">
      #{publish_as_fields(params, source, errors)}
      #{fixed_hashtag_fields(params, source, errors)}
      #{staging_fields(params, source, errors)}
      #{error_message(errors, :mode)}
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

  defp mode_badge(%Source{mode: "automated"} = source, tab) do
    mode_badge_form(source, tab, "setup", "Automated", "badge-processed", "Switch back to setup")
  end

  defp mode_badge(source, tab) do
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
      <input type="hidden" name="tab" value="#{escape_attr(tab)}">
      <button type="submit" name="mode" value="#{escape_attr(next_mode)}" class="badge #{class}" title="#{escape_attr(title)}">#{label}</button>
    </form>
    """
  end

  defp fixed_hashtag_fields(params, source, errors) do
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
             value="#{escape_attr(tags)}" placeholder="comma-separated">
      #{error_message(errors, :fixed_hashtags)}
      <p class="help-text">
        Added to every published article as <code>t</code> tags.
        Duplicates of article hashtags are dropped.
      </p>
    </div>
    """
  end

  defp staging_fields(params, source, errors) do
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
               value="#{escape_attr(to_string(hold))}">
        #{error_message(errors, :staging_hold_minutes)}
        <p class="help-text">
          After an article enters staging, automated export waits this long.
          0 publishes on the next scheduler run. Manual Publish ignores the hold.
          Setup sources never auto-publish.
        </p>
      </div>
      <div class="form-group">
        <label for="notify_pubkey">Notify pubkey</label>
        <input type="text" id="notify_pubkey" name="notify_pubkey" placeholder="npub1… or hex"
               value="#{escape_attr(notify)}" autocomplete="off">
        #{error_message(errors, :notify_pubkey)}
        <p class="help-text">
          Optional. Receives a NIP-17 DM when an article first enters staging or is revised.
          Delivered to the recipient’s NIP-05 relays (or the public list if none are advertised),
          plus any extra relays in <code>NOSTR_RELAYS_INBOX</code>.
        </p>
      </div>
    </fieldset>
    """
  end

  defp publish_as_fields(params, source, errors) do
    publish_as = params["publish_as"] || (source && source.publish_as) || "draft"
    draft_checked = if publish_as == "draft", do: "checked", else: ""
    plain_checked = if publish_as == "draft_plain", do: "checked", else: ""
    article_checked = if publish_as == "article", do: "checked", else: ""
    video_checked = if publish_as == "video", do: "checked", else: ""
    draft_hidden = if publish_as in ["draft", "draft_plain"], do: "", else: "hidden"
    article_hidden = if publish_as in ["article", "video"], do: "", else: "hidden"
    video_hidden = if publish_as == "video", do: "", else: "hidden"
    mirror_media = params["mirror_media"] || option(source, "mirror_media") || "blossom"
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
               value="#{escape_attr(pubkey)}" autocomplete="off">
        #{error_message(errors, :pubkey)}
        <p class="help-text">Required for drafts. Added as a <code>p</code> tag so the intended author is known.</p>
      </div>
    </div>
    <div id="article-signer-fields" #{article_hidden}>
      <div class="form-group">
        <label for="signing_nsec">Author private key (nsec)</label>
        <input type="password" id="signing_nsec" name="signing_nsec" autocomplete="new-password"
               placeholder="#{if nsec_set?, do: "Configured — paste a new key to replace", else: "nsec1…"}">
        #{error_message(errors, :signing_nsec)}
        <p class="help-text">Required for articles and videos unless a bunker URL is set. Stored encrypted.</p>
      </div>
      <div class="form-group">
        <label for="bunker_connection">Bunker URL</label>
        <input type="text" id="bunker_connection" name="bunker_connection"
               placeholder="bunker://…?relay=wss://…"
               value="#{escape_attr(bunker)}" autocomplete="off">
        <p class="help-text">
          Alternative to an nsec. Unattended publishing works only if the remote signer auto-approves requests.
        </p>
      </div>
    </div>
    #{publish_as_script()}
    """
  end

  defp publish_as_script do
    """
    <script>
    (function () {
      const draft = document.getElementById("draft-author-fields");
      const article = document.getElementById("article-signer-fields");
      const video = document.getElementById("video-hosting-fields");
      const radios = document.querySelectorAll("input[name='publish_as']");
      if (!radios.length) return;
      function sync() {
        const selected = document.querySelector("input[name='publish_as']:checked");
        const value = selected ? selected.value : "draft";
        if (draft) draft.hidden = value !== "draft" && value !== "draft_plain";
        if (article) article.hidden = value !== "article" && value !== "video";
        if (video) video.hidden = value !== "video";
        if (window.rss2nostrSyncAddSourceSubmit) window.rss2nostrSyncAddSourceSubmit();
      }
      radios.forEach(function (radio) { radio.addEventListener("change", sync); });
      sync();
    })();
    </script>
    """
  end

  defp start_label(source, start_guid, start_at) do
    cond do
      start_guid not in [nil, ""] -> start_guid
      start_at not in [nil, ""] -> start_at
      source.publish_after_date -> datetime_value(source.publish_after_date)
      true -> "beginning of the feed"
    end
  end

  defp datetime_value(nil), do: ""
  defp datetime_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp datetime_value(value) when is_binary(value), do: value

  defp status_class(status) do
    case status do
      0 -> "badge-new"
      1 -> "badge-processing"
      2 -> "badge-processed"
      6 -> "badge-published"
      9 -> "badge-pending-images"
      _ -> "badge-error"
    end
  end

  defp format_datetime(nil), do: "-"
  defp format_datetime(dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")

  defp feed_start_script do
    """
    <script>
    (function () {
      const select = document.getElementById("start_article");
      const urlInput = document.getElementById("url");
      const startGuid = document.getElementById("start_guid");
      const startPublished = document.getElementById("start_published_at");
      if (!select || !urlInput || !urlInput.value) return;

      fetch("/api/sources/preview", {
        method: "POST",
        headers: { "content-type": "application/json", "accept": "application/json" },
        body: JSON.stringify({ url: urlInput.value })
      }).then(function (res) {
        return res.json().then(function (body) {
          if (!res.ok) throw new Error(body.error || "Could not load articles.");
          return body;
        });
      }).then(function (body) {
        const items = body.items || [];
        const current = startGuid ? startGuid.value : "";
        select.innerHTML = "";
        const any = document.createElement("option");
        any.value = "";
        any.textContent = "Beginning of the feed";
        select.appendChild(any);
        items.forEach(function (item) {
          const option = document.createElement("option");
          option.value = item.guid || item.link || "";
          option.dataset.publishedAt = item.published_at || "";
          option.textContent = (item.published_at ? item.published_at.slice(0, 10) + " — " : "") +
            (item.title || item.guid || "Untitled");
          if (current && option.value === current) option.selected = true;
          select.appendChild(option);
        });
      }).catch(function (err) {
        select.innerHTML = "";
        const option = document.createElement("option");
        option.value = "";
        option.textContent = (err && err.message) ? err.message : "Could not load articles";
        select.appendChild(option);
      });

      select.addEventListener("change", function () {
        const option = select.options[select.selectedIndex];
        if (startGuid) startGuid.value = select.value || "";
        if (startPublished) {
          startPublished.value = option && option.dataset.publishedAt ? option.dataset.publishedAt : "";
        }
      });
    })();
    </script>
    """
  end

  def language_select(selected) do
    selected = selected || "de"

    options =
      language_choices()
      |> maybe_include_current_language(selected)
      |> Enum.map_join("", fn {code, label} ->
        sel = if code == selected, do: " selected", else: ""
        ~s(<option value="#{escape_attr(code)}"#{sel}>#{escape_html(label)}</option>)
      end)

    """
    <select id="language" name="language">
      #{options}
    </select>
    """
  end

  defp maybe_include_current_language(choices, selected) do
    if Enum.any?(choices, fn {code, _} -> code == selected end) do
      choices
    else
      [{selected, selected} | choices]
    end
  end

  defp language_choices do
    [
      {"ar", "Arabic (ar)"},
      {"bg", "Bulgarian (bg)"},
      {"zh", "Chinese (zh)"},
      {"hr", "Croatian (hr)"},
      {"cs", "Czech (cs)"},
      {"da", "Danish (da)"},
      {"nl", "Dutch (nl)"},
      {"en", "English (en)"},
      {"et", "Estonian (et)"},
      {"fi", "Finnish (fi)"},
      {"fr", "French (fr)"},
      {"de", "German (de)"},
      {"el", "Greek (el)"},
      {"he", "Hebrew (he)"},
      {"hi", "Hindi (hi)"},
      {"hu", "Hungarian (hu)"},
      {"id", "Indonesian (id)"},
      {"it", "Italian (it)"},
      {"ja", "Japanese (ja)"},
      {"ko", "Korean (ko)"},
      {"lv", "Latvian (lv)"},
      {"lt", "Lithuanian (lt)"},
      {"no", "Norwegian (no)"},
      {"fa", "Persian (fa)"},
      {"pl", "Polish (pl)"},
      {"pt", "Portuguese (pt)"},
      {"ro", "Romanian (ro)"},
      {"ru", "Russian (ru)"},
      {"sr", "Serbian (sr)"},
      {"sk", "Slovak (sk)"},
      {"sl", "Slovenian (sl)"},
      {"es", "Spanish (es)"},
      {"sv", "Swedish (sv)"},
      {"th", "Thai (th)"},
      {"tr", "Turkish (tr)"},
      {"uk", "Ukrainian (uk)"},
      {"vi", "Vietnamese (vi)"}
    ]
  end

  defp flash_notice(nil, _), do: ""
  defp flash_notice("", _), do: ""

  defp flash_notice(notice, kind) do
    class =
      case kind do
        "error" -> "error"
        "warning" -> "warning"
        _ -> "success"
      end

    ~s(<p class="#{class}">#{escape_html(notice)}</p>)
  end

  defp error_message(errors, field) do
    case errors[field] do
      nil -> ""
      msgs when is_list(msgs) -> "<span class=\"error\">#{Enum.join(msgs, ", ")}</span>"
      msg -> "<span class=\"error\">#{msg}</span>"
    end
  end

  defp escape_html(str) when is_binary(str) do
    str
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp escape_html(nil), do: ""

  defp escape_attr(nil), do: ""

  defp escape_attr(str) when is_binary(str) do
    str
    |> String.replace("&", "&amp;")
    |> String.replace("\"", "&quot;")
    |> String.replace("<", "&lt;")
  end

  defp escape_attr(_), do: ""

  defp discover_script do
    """
    <script>
    (function () {
      const website = document.getElementById("website");
      const discoverButton = document.getElementById("discover-button");
      const statusEl = document.getElementById("discover-status");
      const errorEl = document.getElementById("discover-error");
      const details = document.getElementById("source-details");
      const feedsList = document.getElementById("feeds-list");
      const nameInput = document.getElementById("name");
      const urlInput = document.getElementById("url");
      const typeInput = document.getElementById("type");
      const startSelect = document.getElementById("start_article");
      const startGuid = document.getElementById("start_guid");
      const startPublished = document.getElementById("start_published_at");
      const languageSelect = document.getElementById("language");
      const submit = document.getElementById("submit-source");

      function present(value) {
        return !!(value && String(value).trim());
      }

      function selectedPublishAs() {
        const selected = document.querySelector("#add-source-form input[name='publish_as']:checked");
        return selected ? selected.value : "draft";
      }

      function identityOk() {
        if (selectedPublishAs() === "article" || selectedPublishAs() === "video") {
          const nsec = document.getElementById("signing_nsec");
          const bunker = document.getElementById("bunker_connection");
          return present(nsec && nsec.value) || present(bunker && bunker.value);
        }
        if (selectedPublishAs() === "draft" || selectedPublishAs() === "draft_plain") {
          const pubkey = document.getElementById("pubkey");
          return present(pubkey && pubkey.value);
        }
        return false;
      }

      function startOk() {
        if (!startSelect) return false;
        const option = startSelect.selectedOptions[0];
        if (!option) return false;
        const label = option.textContent || "";
        if (label.indexOf("Loading articles") !== -1) return false;
        if (label.indexOf("No articles found") !== -1) return true;
        return present(option.value);
      }

      function formComplete() {
        const detailsReady = details && !details.hidden;
        return detailsReady &&
          present(nameInput && nameInput.value) &&
          present(urlInput && urlInput.value) &&
          present(languageSelect && languageSelect.value) &&
          startOk() &&
          identityOk();
      }

      function syncSubmit() {
        if (!submit) return;
        submit.disabled = !formComplete();
      }

      window.rss2nostrSyncAddSourceSubmit = syncSubmit;

      function showError(message) {
        errorEl.hidden = false;
        errorEl.textContent = message;
      }

      function hideError() {
        errorEl.hidden = true;
        errorEl.textContent = "";
      }

      function setStatus(message) {
        statusEl.textContent = message || "";
      }

      function applyLanguage(code) {
        if (!languageSelect || !code) return;
        const value = String(code).trim().toLowerCase();
        if (!value) return;
        let option = Array.from(languageSelect.options).find(function (opt) {
          return opt.value === value;
        });
        if (!option) {
          option = document.createElement("option");
          option.value = value;
          option.textContent = value;
          languageSelect.appendChild(option);
        }
        languageSelect.value = value;
      }

      function languageFrom(body) {
        if (body && body.language) return body.language;
        if (body && body.feeds && body.feeds[0] && body.feeds[0].language) {
          return body.feeds[0].language;
        }
        return "";
      }

      function fillArticles(items) {
        startSelect.innerHTML = "";
        const list = Array.isArray(items) ? items.slice() : [];
        if (list.length === 0) {
          const option = document.createElement("option");
          option.value = "";
          option.textContent = "No articles found in this feed";
          startSelect.appendChild(option);
          startGuid.value = "";
          startPublished.value = "";
          return;
        }

        list.forEach(function (item, index) {
          const option = document.createElement("option");
          option.value = item.guid || item.link || "";
          option.dataset.publishedAt = item.published_at || "";
          const date = item.published_at ? item.published_at.slice(0, 10) + " — " : "";
          option.textContent = date + (item.title || item.guid || "Untitled");
          startSelect.appendChild(option);
          if (index === list.length - 1) {
            option.selected = true;
          }
        });
        syncStartArticle();
      }

      function syncStartArticle() {
        const option = startSelect.selectedOptions[0];
        startGuid.value = option ? option.value : "";
        startPublished.value = option && option.dataset.publishedAt ? option.dataset.publishedAt : "";
      }

      async function previewFeed(url, type) {
        urlInput.value = url;
        if (type) typeInput.value = type;
        startSelect.innerHTML = "";
        const loading = document.createElement("option");
        loading.value = "";
        loading.textContent = "Loading articles…";
        startSelect.appendChild(loading);
        startGuid.value = "";
        startPublished.value = "";
        syncSubmit();
        setStatus("Loading articles…");
        const res = await fetch("/api/sources/preview", {
          method: "POST",
          headers: { "content-type": "application/json", "accept": "application/json" },
          body: JSON.stringify({ url: url })
        });
        const body = await res.json().catch(function () { return {}; });
        if (!res.ok) {
          fillArticles([]);
          throw new Error(body.error || "Could not load feed articles.");
        }
        if (body.feeds && body.feeds[0] && body.feeds[0].type) {
          typeInput.value = body.feeds[0].type;
        }
        applyLanguage(languageFrom(body));
        fillArticles(body.items || []);
        setStatus("");
        syncSubmit();
        if (window.rss2nostrScheduleComposePreview) window.rss2nostrScheduleComposePreview();
      }

      function renderFeeds(feeds, selectedUrl) {
        feedsList.innerHTML = "";
        feeds.forEach(function (feed, index) {
          const id = "feed-" + index;
          const label = document.createElement("label");
          label.className = "choice";
          const input = document.createElement("input");
          input.type = "radio";
          input.name = "feed_choice";
          input.id = id;
          input.value = feed.url;
          input.dataset.type = feed.type || "";
          if (feed.url === selectedUrl || (!selectedUrl && index === 0)) input.checked = true;
          const text = document.createElement("span");
          const title = document.createElement("strong");
          title.textContent = feed.title || "Untitled feed";
          const code = document.createElement("code");
          code.className = "url";
          code.textContent = feed.url;
          text.appendChild(title);
          text.appendChild(code);
          label.appendChild(input);
          label.appendChild(text);
          feedsList.appendChild(label);
          input.addEventListener("change", function () {
            previewFeed(feed.url, feed.type).catch(function (err) {
              showError(err.message);
            });
          });
        });
      }

      discoverButton.addEventListener("click", async function () {
        hideError();
        discoverButton.disabled = true;
        setStatus("Looking for feeds…");
        try {
          const res = await fetch("/api/sources/discover", {
            method: "POST",
            headers: { "content-type": "application/json", "accept": "application/json" },
            body: JSON.stringify({ url: website.value })
          });
          const body = await res.json().catch(function () { return {}; });
          if (!res.ok) {
            throw new Error(body.error || "Could not find feeds.");
          }
          const feeds = body.feeds || [];
          if (feeds.length === 0) {
            throw new Error("No RSS or Atom feeds found on this page.");
          }
          details.hidden = false;
          if (!nameInput.value && body.page_title) {
            nameInput.value = body.page_title;
          }
          const selected = (feeds[0] && feeds[0].url) || "";
          renderFeeds(feeds, selected);
          if (body.direct_feed) {
            setStatus("Using this feed URL.");
          }
          if (body.items && body.items.length) {
            urlInput.value = selected;
            if (feeds[0].type) typeInput.value = feeds[0].type;
            applyLanguage(languageFrom(body));
            fillArticles(body.items);
            syncSubmit();
            if (!body.direct_feed) setStatus("");
            if (window.rss2nostrScheduleComposePreview) window.rss2nostrScheduleComposePreview();
          } else {
            await previewFeed(selected, feeds[0].type);
          }
        } catch (err) {
          showError((err && err.message) ? err.message : "Could not find feeds.");
          setStatus("");
        } finally {
          discoverButton.disabled = false;
        }
      });

      startSelect.addEventListener("change", function () {
        syncStartArticle();
        syncSubmit();
        if (window.rss2nostrScheduleComposePreview) window.rss2nostrScheduleComposePreview();
      });

      const addForm = document.getElementById("add-source-form");
      if (addForm) {
        addForm.addEventListener("submit", function (event) {
          syncSubmit();
          if (submit && submit.disabled) event.preventDefault();
        });
      }

      website.addEventListener("keydown", function (event) {
        if (event.key === "Enter") {
          event.preventDefault();
          discoverButton.click();
        }
      });

      ["name", "pubkey", "signing_nsec", "bunker_connection"].forEach(function (id) {
        const el = document.getElementById(id);
        if (!el) return;
        el.addEventListener("input", syncSubmit);
        el.addEventListener("change", syncSubmit);
      });
      document.querySelectorAll("#add-source-form input[name='publish_as']").forEach(function (radio) {
        radio.addEventListener("change", syncSubmit);
      });
      syncSubmit();
    })();
    </script>
    """
  end

  defp compose_layout(params, source) do
    """
    <div class="compose-layout">
      <div>
        #{compose_fields(params, source)}
      </div>
      #{compose_preview_panel()}
    </div>
    """
  end

  defp compose_fields(params, source) do
    fetch =
      params["fetch_source_from"] || (source && source.fetch_source_from) || "fetch_from_url"

    selector =
      params["body_selector"] ||
        option(source, "body_selector") ||
        BodySchema.selector_for_url(source && source.url) ||
        ""
    start_at = params["start_at"] || option(source, "start_at") || ""
    skip = params["skip_classes"] || skip_classes_text(source)
    content_checked = if fetch == "content", do: "checked", else: ""
    url_checked = if fetch != "content", do: "checked", else: ""

    presets =
      Enum.map_join(Composer.body_presets(), "", fn {label, value} ->
        selected = if value != "" and value == selector, do: " selected", else: ""
        ~s(<option value="#{escape_attr(value)}"#{selected}>#{escape_html(label)}</option>)
      end)

    """
    <fieldset class="compose-fieldset">
      <legend>Article text</legend>
      <div class="choice-list">
        <label class="choice">
          <input type="radio" name="fetch_source_from" value="content" #{content_checked}>
          <span>
            <strong>Contained in the feed XML</strong>
            <span class="help-text">Use content:encoded or the Atom content from the feed.</span>
          </span>
        </label>
        <label class="choice">
          <input type="radio" name="fetch_source_from" value="fetch_from_url" #{url_checked}>
          <span>
            <strong>Fetch from the article website</strong>
            <span class="help-text">Download the article page, then pick the block that is the article.</span>
          </span>
        </label>
      </div>
    </fieldset>

    <details id="body-regions-details" class="compose-advanced"
             data-known-selectors="#{escape_attr(Enum.join(BodySchema.known_selectors(), ","))}"
             data-url-schema="#{escape_attr(to_string(BodySchema.selector_for_url(source && source.url) || ""))}"
             #{if known_body_schema?(selector, source), do: "", else: "open"}>
      <summary>Which block is the article?</summary>
      <p class="help-text">
        Click the region that looks like the article body. Known sites such as
        Substack are preselected from the article URL.
      </p>
      <input type="hidden" id="body_selector" name="body_selector" value="#{escape_attr(selector)}">
      <div id="body-regions" class="body-regions">
        <p class="help-text">Load an article to see candidate regions.</p>
      </div>
    </details>

    <details class="compose-advanced">
      <summary>Start here</summary>
      <p class="help-text">Click the first line that should appear in the body. Everything before it is dropped.</p>
      <input type="hidden" id="start_at" name="start_at" value="#{escape_attr(to_string(start_at))}">
      <div id="start-blocks" class="start-blocks">
        <p class="help-text">Load an article to see opening lines.</p>
      </div>
    </details>

    <details class="compose-advanced">
      <summary>Technical settings</summary>
      <div class="form-group">
        <label for="body_preset">Body selector preset</label>
        <select id="body_preset">
          #{presets}
        </select>
      </div>
      <div class="form-group">
        <label for="body_selector_text">Body CSS selector</label>
        <input type="text" id="body_selector_text"
               placeholder="article, div.entry-content, …"
               value="#{escape_attr(selector)}" autocomplete="off">
        <p class="help-text">Leave empty to convert the whole HTML.</p>
      </div>
      <div class="form-group">
        <label for="start_at_text">Start at (XPath)</label>
        <input type="text" id="start_at_text" value="#{escape_attr(to_string(start_at))}" autocomplete="off">
      </div>
      <div class="form-group">
        <label for="skip_classes">Skip these CSS classes</label>
        <textarea id="skip_classes" name="skip_classes" rows="3">#{escape_html(skip)}</textarea>
        <p class="help-text">Comma-separated class names to drop (ads, comments, teasers).</p>
      </div>
    </details>
    """
  end

  defp compose_preview_panel do
    """
    <div class="compose-preview-panel">
      <div class="compose-preview-header">
        <label>Nostr event preview</label>
        <div class="compose-preview-actions">
          <div class="compose-tabs" role="tablist">
            <button type="button" class="compose-tab is-active" data-preview-tab="rendered" role="tab" aria-selected="true">Preview</button>
            <button type="button" class="compose-tab" data-preview-tab="source" role="tab" aria-selected="false">Markdown</button>
            <button type="button" class="compose-tab" data-preview-tab="event" role="tab" aria-selected="false">Event</button>
          </div>
          <label id="compose-split-toggle" class="compose-split-toggle" hidden>
            <input type="checkbox" id="show-split-parts">
            Show split parts
          </label>
          <button type="button" class="btn btn-small btn-secondary" id="refresh-preview">Refresh</button>
        </div>
      </div>
      <p id="compose-preview-status" class="help-text">Pick an article to preview the Markdown.</p>
      <div id="compose-preview-meta" class="compose-preview-meta" hidden></div>
      <div id="compose-preview-hero" class="compose-hero" hidden></div>
      <article id="compose-preview-rendered" class="compose-preview-rendered" hidden></article>
      <div id="compose-preview" class="compose-preview" hidden></div>
      <pre id="compose-preview-event" class="compose-preview" hidden></pre>
    </div>
    """
  end

  defp compose_script do
    """
    <script>
    (function () {
      const urlInput = document.getElementById("url");
      const previewEl = document.getElementById("compose-preview");
      const renderedEl = document.getElementById("compose-preview-rendered");
      const eventEl = document.getElementById("compose-preview-event");
      if (!urlInput || !previewEl || !renderedEl) return;
      const sourceId = document.getElementById("source_id");

      const articleSelect = document.getElementById("start_article") || document.getElementById("preview_article");
      const statusEl = document.getElementById("compose-preview-status");
      const metaEl = document.getElementById("compose-preview-meta");
      const heroEl = document.getElementById("compose-preview-hero");
      const refresh = document.getElementById("refresh-preview");
      const preset = document.getElementById("body_preset");
      const selector = document.getElementById("body_selector");
      const selectorText = document.getElementById("body_selector_text");
      const startAt = document.getElementById("start_at");
      const startAtText = document.getElementById("start_at_text");
      const skip = document.getElementById("skip_classes");
      const regionsEl = document.getElementById("body-regions");
      const startBlocksEl = document.getElementById("start-blocks");
      const fetchRadios = document.querySelectorAll("input[name='fetch_source_from']");
      const tabs = document.querySelectorAll("[data-preview-tab]");
      const splitToggle = document.getElementById("compose-split-toggle");
      const splitInput = document.getElementById("show-split-parts");
      let timer = null;
      let activeTab = "rendered";
      let bodyChosen = !!(selector && selector.value.trim());
      let lastPreview = null;
      let showSplitParts = false;

      function articleGuid() {
        return articleSelect ? (articleSelect.value || "") : "";
      }

      function payload() {
        const fetchFrom = document.querySelector("input[name='fetch_source_from']:checked");
        return {
          url: urlInput.value,
          guid: articleGuid(),
          fetch_source_from: fetchFrom ? fetchFrom.value : "fetch_from_url",
          body_selector: selector ? selector.value : "",
          body_selector_auto: bodyChosen ? "false" : "true",
          start_at: startAt ? startAt.value : "",
          skip_classes: skip ? skip.value : "",
          source_id: sourceId ? sourceId.value : ""
        };
      }

      function setSelector(value) {
        if (selector) selector.value = value || "";
        if (selectorText) selectorText.value = value || "";
        syncPreset();
        syncBodyRegionsOpen();
      }

      function knownSelectors() {
        const details = document.getElementById("body-regions-details");
        const raw = (details && details.getAttribute("data-known-selectors")) || "";
        return new Set(raw.split(",").map(function (s) { return s.trim(); }).filter(Boolean));
      }

      function schemaApplied() {
        const details = document.getElementById("body-regions-details");
        const value = selector ? selector.value.trim() : "";
        const urlSchema = (details && details.getAttribute("data-url-schema")) || "";
        if (value && knownSelectors().has(value)) return true;
        if (!value && !bodyChosen && urlSchema) return true;
        return false;
      }

      function syncBodyRegionsOpen() {
        const details = document.getElementById("body-regions-details");
        if (!details) return;
        details.open = !schemaApplied();
      }

      function setStartAt(value) {
        if (startAt) startAt.value = value || "";
        if (startAtText) startAtText.value = value || "";
      }

      function syncPreset() {
        if (!preset || !selector) return;
        const match = Array.from(preset.options).find(function (opt) {
          return opt.value && opt.value === selector.value;
        });
        preset.value = match ? match.value : "";
      }

      function setPreviewStatus(message) {
        if (statusEl) statusEl.textContent = message || "";
      }

      function selectedArticleLink() {
        if (!articleSelect || !articleSelect.selectedOptions[0]) return "";
        return articleSelect.selectedOptions[0].dataset.link || "";
      }

      function setOriginalArticle(url) {
        document.querySelectorAll("[data-original-article]").forEach(function (el) {
          const a = el.querySelector("a");
          if (!url) {
            el.hidden = true;
            if (a) {
              a.removeAttribute("href");
              a.removeAttribute("title");
            }
            return;
          }
          el.hidden = false;
          if (a) {
            a.href = url;
            a.title = url;
          }
        });
      }

      window.rss2nostrSetOriginalArticle = setOriginalArticle;

      async function runPreview() {
        if (!urlInput.value) return;
        setPreviewStatus("Building preview…");
        previewEl.hidden = true;
        renderedEl.hidden = true;
        if (eventEl) eventEl.hidden = true;
        if (metaEl) metaEl.hidden = true;
        if (heroEl) {
          heroEl.hidden = true;
          heroEl.replaceChildren();
        }
        try {
          const res = await fetch("/api/sources/compose-preview", {
            method: "POST",
            headers: { "content-type": "application/json", "accept": "application/json" },
            body: JSON.stringify(payload())
          });
          const body = await res.json().catch(function () { return {}; });
          if (!res.ok) throw new Error(body.error || "Could not build preview.");
          renderPreview(body);
          setPreviewStatus("");
        } catch (err) {
          setPreviewStatus((err && err.message) ? err.message : "Could not build preview.");
        }
      }

      function previewParts(body) {
        return body.nostr_parts_preview || [];
      }

      function renderHero(body) {
        if (!heroEl) return;
        heroEl.replaceChildren();
        if (!body.image) {
          heroEl.hidden = true;
          return;
        }
        const img = document.createElement("img");
        img.src = body.image;
        img.alt = body.title || "";
        heroEl.appendChild(img);
        heroEl.hidden = false;
      }

      function appendHtml(parent, html, markdown) {
        const wrap = document.createElement("div");
        wrap.innerHTML = html || "";
        if (!html && markdown) {
          const fallback = document.createElement("p");
          fallback.textContent = markdown;
          wrap.appendChild(fallback);
        }
        if (!html && !markdown) {
          const empty = document.createElement("p");
          empty.textContent = "(empty)";
          wrap.appendChild(empty);
        }
        parent.appendChild(wrap);
      }

      function partLabel(part) {
        return "Part " + part.index + "/" + part.total;
      }

      function renderArticlePreview(body) {
        const parts = previewParts(body);
        const split = showSplitParts && parts.length > 1;

        renderedEl.replaceChildren();
        if (split) {
          parts.forEach(function (part) {
            const section = document.createElement("section");
            section.className = "compose-preview-part";
            const label = document.createElement("p");
            label.className = "compose-preview-part-label";
            label.textContent = partLabel(part);
            section.appendChild(label);
            appendHtml(section, part.html, part.markdown);
            renderedEl.appendChild(section);
          });
        } else {
          appendHtml(renderedEl, body.html, body.markdown);
        }

        previewEl.replaceChildren();
        if (split) {
          parts.forEach(function (part) {
            const section = document.createElement("section");
            section.className = "compose-preview-part";
            const label = document.createElement("p");
            label.className = "compose-preview-part-label";
            label.textContent = partLabel(part);
            const pre = document.createElement("pre");
            pre.className = "compose-preview-part-markdown";
            pre.textContent = part.markdown || "(empty)";
            section.appendChild(label);
            section.appendChild(pre);
            previewEl.appendChild(section);
          });
        } else {
          previewEl.textContent = body.markdown || "(empty)";
        }
      }

      function renderPreview(body) {
        lastPreview = body;
        const parts = previewParts(body);
        if (splitToggle) splitToggle.hidden = parts.length <= 1;
        if (parts.length <= 1) {
          showSplitParts = false;
          if (splitInput) splitInput.checked = false;
        }

        setOriginalArticle(body.link || selectedArticleLink());
        renderHero(body);

        if (metaEl) {
          metaEl.hidden = false;
          metaEl.replaceChildren();
          appendMeta(metaEl, "Title", body.title);
          appendMeta(metaEl, "Summary", body.summary);
          appendMeta(metaEl, "Image", body.image);
          if (parts.length > 1) {
            appendMeta(metaEl, "Parts", parts.length + " Nostr events");
          }
          if (selector && selector.value && body.selector_matched === false) {
            appendMeta(metaEl, "Selector", "Did not match; using the full HTML.");
          }
        }

        renderArticlePreview(body);
        if (eventEl) {
          const relays = (body.nostr_relays || []).join("\\n");
          let text = relays ? "Relays:\\n" + relays + "\\n\\n" : "";
          const parts = body.nostr_parts_json || [];
          if (body.nostr_draft && parts.length > 1) {
            text += "This article will be published as " + parts.length +
              " NIP-37 drafts so each published wrap stays within 65535 bytes.\\n\\n";
          } else if (body.nostr_draft) {
            text += "This inner article is NIP-44-encrypted into a kind 31234 wrap when published.\\n\\n";
          } else if (body.nostr_plain_draft) {
            text += "Published as kind 30024, signed by the app key.\\n\\n";
          }
          if (parts.length) {
            parts.forEach(function (json, i) {
              if (parts.length > 1) text += "Part " + (i + 1) + "/" + parts.length + ":\\n";
              text += json + "\\n\\n";
            });
          } else {
            text += body.nostr_event_json || JSON.stringify(body.nostr_event || {}, null, 2);
          }
          eventEl.textContent = text;
        }
        if (!bodyChosen && body.body_selector != null) setSelector(body.body_selector);
        renderRegions(body.body_regions || [], body.body_selector);
        renderStartBlocks(body.start_blocks || []);
        showActiveTab();
      }

      function renderRegions(regions) {
        if (!regionsEl) return;
        regionsEl.replaceChildren();
        if (!regions.length) {
          const empty = document.createElement("p");
          empty.className = "help-text";
          empty.textContent = "No candidate regions found in this article.";
          regionsEl.appendChild(empty);
          return;
        }

        regions.forEach(function (region) {
          const button = document.createElement("button");
          button.type = "button";
          button.className = "body-region" + (region.selected ? " is-selected" : "");
          const title = document.createElement("strong");
          title.textContent = region.label || "Region";
          if (region.recommended) {
            const badge = document.createElement("span");
            badge.className = "body-region-badge";
            badge.textContent = "Preselected for this site";
            title.appendChild(badge);
          }
          const excerpt = document.createElement("span");
          excerpt.className = "help-text";
          excerpt.textContent = region.first_line || "(empty)";
          const meta = document.createElement("span");
          meta.className = "help-text";
          meta.textContent = (region.word_count || 0) + " words";
          button.appendChild(title);
          button.appendChild(excerpt);
          button.appendChild(meta);
          button.addEventListener("click", function () {
            bodyChosen = true;
            setSelector(region.selector || "");
            setStartAt("");
            schedulePreview();
          });
          regionsEl.appendChild(button);
        });
      }

      function renderStartBlocks(blocks) {
        if (!startBlocksEl) return;
        startBlocksEl.replaceChildren();

        const beginning = document.createElement("button");
        beginning.type = "button";
        beginning.className = "start-block" + (!(startAt && startAt.value) ? " is-selected" : "");
        beginning.textContent = "From the beginning";
        beginning.addEventListener("click", function () {
          setStartAt("");
          schedulePreview();
        });
        startBlocksEl.appendChild(beginning);

        if (!blocks.length) {
          const empty = document.createElement("p");
          empty.className = "help-text";
          empty.textContent = "No opening lines found in this region.";
          startBlocksEl.appendChild(empty);
          return;
        }

        blocks.forEach(function (block) {
          const button = document.createElement("button");
          button.type = "button";
          button.className = "start-block" + (block.selected ? " is-selected" : "");
          button.textContent = block.text || "";
          button.addEventListener("click", function () {
            setStartAt(block.xpath || "");
            schedulePreview();
          });
          startBlocksEl.appendChild(button);
        });
      }

      function appendMeta(parent, label, value) {
        if (!value) return;
        const row = document.createElement("div");
        const name = document.createElement("strong");
        name.textContent = label + ": ";
        row.appendChild(name);
        row.appendChild(document.createTextNode(value));
        parent.appendChild(row);
      }

      function showActiveTab() {
        const showRendered = activeTab === "rendered";
        const showMarkdown = activeTab === "source";
        const showEvent = activeTab === "event";
        renderedEl.hidden = !showRendered;
        previewEl.hidden = !showMarkdown;
        if (eventEl) eventEl.hidden = !showEvent;
        if (metaEl) metaEl.hidden = showEvent || !metaEl.childElementCount;
        tabs.forEach(function (tab) {
          const selected = tab.getAttribute("data-preview-tab") === activeTab;
          tab.classList.toggle("is-active", selected);
          tab.setAttribute("aria-selected", selected ? "true" : "false");
        });
      }

      function schedulePreview() {
        clearTimeout(timer);
        timer = setTimeout(runPreview, 400);
      }

      if (preset) {
        preset.addEventListener("change", function () {
          bodyChosen = true;
          setSelector(preset.value);
          setStartAt("");
          schedulePreview();
        });
      }
      if (selectorText) {
        selectorText.addEventListener("input", function () {
          bodyChosen = true;
          setSelector(selectorText.value);
          schedulePreview();
        });
      }
      if (startAtText) {
        startAtText.addEventListener("input", function () {
          setStartAt(startAtText.value);
          schedulePreview();
        });
      }

      if (skip) skip.addEventListener("input", schedulePreview);
      fetchRadios.forEach(function (radio) {
        radio.addEventListener("change", schedulePreview);
      });
      if (articleSelect && articleSelect.id === "preview_article") {
        articleSelect.addEventListener("change", function () {
          setOriginalArticle(selectedArticleLink());
          schedulePreview();
        });
      }
      if (refresh) refresh.addEventListener("click", runPreview);
      if (splitInput) {
        splitInput.addEventListener("change", function () {
          showSplitParts = splitInput.checked;
          if (lastPreview) renderArticlePreview(lastPreview);
        });
      }
      tabs.forEach(function (tab) {
        tab.addEventListener("click", function () {
          activeTab = tab.getAttribute("data-preview-tab") || "rendered";
          showActiveTab();
        });
      });

      window.rss2nostrScheduleComposePreview = schedulePreview;
      window.rss2nostrRunComposePreview = runPreview;
    })();
    </script>
    """
  end

  defp compose_page_script do
    """
    <script>
    (function () {
      const select = document.getElementById("preview_article");
      const urlInput = document.getElementById("url");
      if (!select || !urlInput || !urlInput.value) return;

      fetch("/api/sources/preview", {
        method: "POST",
        headers: { "content-type": "application/json", "accept": "application/json" },
        body: JSON.stringify({ url: urlInput.value })
      }).then(function (res) {
        return res.json().then(function (body) {
          if (!res.ok) throw new Error(body.error || "Could not load articles.");
          return body;
        });
      }).then(function (body) {
        const items = body.items || [];
        select.innerHTML = "";
        if (items.length === 0) {
          const option = document.createElement("option");
          option.value = "";
          option.textContent = "No articles found in this feed";
          select.appendChild(option);
          return;
        }
        items.forEach(function (item, index) {
          const option = document.createElement("option");
          option.value = item.guid || item.link || "";
          if (item.link) option.dataset.link = item.link;
          option.textContent = (item.published_at ? item.published_at.slice(0, 10) + " — " : "") +
            (item.title || item.guid || "Untitled");
          if (index === 0) option.selected = true;
          select.appendChild(option);
        });
        const selected = select.selectedOptions[0];
        if (window.rss2nostrSetOriginalArticle) {
          window.rss2nostrSetOriginalArticle(selected && selected.dataset.link);
        }
        if (window.rss2nostrScheduleComposePreview) window.rss2nostrScheduleComposePreview();
      }).catch(function (err) {
        select.innerHTML = "";
        const option = document.createElement("option");
        option.value = "";
        option.textContent = (err && err.message) ? err.message : "Could not load articles";
        select.appendChild(option);
      });
    })();
    </script>
    """
  end

  defp known_body_schema?(selector, source) do
    sel = selector |> to_string() |> String.trim()
    url = source && Map.get(source, :url)

    BodySchema.known_selector?(sel) or
      (sel == "" and is_binary(BodySchema.selector_for_url(url)))
  end

  defp option(nil, _key), do: nil

  defp option(source, key) do
    options = source.options || %{}
    options[key]
  end

  defp skip_classes_text(nil), do: Composer.default_skip_classes_text()

  defp skip_classes_text(source) do
    case option(source, "skip_classes") do
      nil -> Composer.default_skip_classes_text()
      list when is_list(list) -> Enum.join(list, ", ")
      text when is_binary(text) -> text
      _ -> Composer.default_skip_classes_text()
    end
  end

  defp public_checked?(params, source) do
    cond do
      params["public"] in ["true", "on", "1"] ->
        true

      params["public"] in ["false", "off", "0"] ->
        false

      is_map(params) and map_size(params) > 0 and Map.has_key?(params, "public") ->
        false

      true ->
        source.public
    end
  end

  @avatar_placeholder "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='32' height='32'%3E%3Crect fill='%23e5e7eb' width='32' height='32' rx='16'/%3E%3C/svg%3E"

  defp source_name_cell(source) do
    pubkey = Signer.author_pubkey(source)
    attrs = if pubkey, do: ~s( data-pubkey="#{escape_attr(pubkey)}"), else: ""

    """
    <div class="source-author">
      <img class="source-avatar" src="#{@avatar_placeholder}" alt="" width="32" height="32"#{attrs}
           onerror="this.onerror=null;this.src='#{@avatar_placeholder}'">
      <span>#{escape_html(source.name)}</span>
    </div>
    """
  end

  defp avatar_relays do
    (Relays.draft() ++ Relays.test() ++ Relays.public())
    |> Enum.uniq()
    |> Enum.take(4)
    |> Enum.join(",")
  end

  defp relay_target_label(:draft), do: "Draft relays"
  defp relay_target_label(:public), do: "Public relays"
  defp relay_target_label(_), do: "Test relays"

  defp relay_badge_class(:public), do: "badge-public"
  defp relay_badge_class(_), do: "badge-test"

  defp relay_target_name(:draft), do: "draft relays"
  defp relay_target_name(:public), do: "public relays"
  defp relay_target_name(_), do: "test relays"

  defp source_avatar_script do
    """
    <script>
    (function () {
      const table = document.getElementById("sources-table");
      if (!table) return;
      const imgs = Array.prototype.slice.call(table.querySelectorAll("img.source-avatar[data-pubkey]"));
      if (!imgs.length) return;

      const relays = (table.getAttribute("data-relays") || "").split(",").map(function (s) { return s.trim(); }).filter(Boolean);
      const byAuthor = {};
      imgs.forEach(function (img) {
        const pubkey = img.getAttribute("data-pubkey");
        if (!pubkey) return;
        (byAuthor[pubkey] = byAuthor[pubkey] || []).push(img);
        try {
          const cached = sessionStorage.getItem("rss2nostr-avatar-" + pubkey);
          if (cached) img.src = cached;
        } catch (e) {}
      });

      const authors = Object.keys(byAuthor);
      if (!authors.length || !relays.length) return;

      relays.forEach(function (url) {
        let ws;
        try { ws = new WebSocket(url); } catch (e) { return; }
        const sub = "src-avatars";
        ws.onopen = function () {
          ws.send(JSON.stringify(["REQ", sub, { kinds: [0], authors: authors }]));
        };
        ws.onmessage = function (event) {
          let msg;
          try { msg = JSON.parse(event.data); } catch (e) { return; }
          if (msg[0] === "EVENT" && msg[2] && msg[2].kind === 0) {
            applyProfile(msg[2]);
          }
          if (msg[0] === "EOSE") {
            try { ws.send(JSON.stringify(["CLOSE", sub])); } catch (e) {}
            try { ws.close(); } catch (e) {}
          }
        };
      });

      function applyProfile(event) {
        let content;
        try { content = JSON.parse(event.content || "{}"); } catch (e) { return; }
        const picture = content.picture;
        if (!picture) return;
        const created = event.created_at || 0;
        (byAuthor[event.pubkey] || []).forEach(function (img) {
          const prev = Number(img.getAttribute("data-created-at") || 0);
          if (created < prev) return;
          img.setAttribute("data-created-at", String(created));
          img.src = picture;
          try { sessionStorage.setItem("rss2nostr-avatar-" + event.pubkey, picture); } catch (e) {}
        });
      }
    })();
    </script>
    """
  end

  defp truncate(str, max) when is_binary(str) do
    if String.length(str) > max do
      String.slice(str, 0, max) <> "..."
    else
      str
    end
  end

  defp truncate(nil, _max), do: ""
end
