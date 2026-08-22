defmodule Rss2Nostr.Web.Views.Sources.Scripts do
  @moduledoc false

  @spec articles_upload_script() :: String.t()
  def articles_upload_script do
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


  @spec publish_as_script() :: String.t()
  def publish_as_script do
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


  @spec feed_start_script() :: String.t()
  def feed_start_script do
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


  @spec discover_script() :: String.t()
  def discover_script do
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
        if (window.rss2nostrScheduleComposePreview) window.rss2nostrScheduleComposePreview();
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


  @spec compose_script() :: String.t()
  def compose_script do
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
      const excludedHashtags = document.getElementById("excluded_hashtags");
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
          excluded_hashtags: excludedHashtags ? excludedHashtags.value : "",
          source_id: sourceId ? sourceId.value : "",
          language: (document.getElementById("language") || {}).value || ""
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
          appendMeta(metaEl, "Hashtags", formatHashtags(body.hashtags));
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

      function formatHashtags(tags) {
        if (!tags || !tags.length) return "none";
        return tags.map(function (tag) { return "#" + tag; }).join(", ");
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
      if (excludedHashtags) excludedHashtags.addEventListener("input", schedulePreview);
      fetchRadios.forEach(function (radio) {
        radio.addEventListener("change", schedulePreview);
      });
      const languageSelect = document.getElementById("language");
      if (languageSelect) languageSelect.addEventListener("change", schedulePreview);
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


  @spec compose_page_script() :: String.t()
  def compose_page_script do
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


  @spec source_avatar_script() :: String.t()
  def source_avatar_script do
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


end
