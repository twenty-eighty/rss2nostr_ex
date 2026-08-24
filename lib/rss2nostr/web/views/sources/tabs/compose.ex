defmodule Rss2Nostr.Web.Views.Sources.Tabs.Compose do
  @moduledoc false

  alias Rss2Nostr.Processing.{BodySchema, Composer}
  alias Rss2Nostr.Web.Views.Sources.{Fields, Helpers, Scripts}

  def compose_tab(source, params, errors) do
    """
    <form action="/sources/#{source.id}" method="POST" class="form form-wide form-compose" id="compose-source-form">
      <input type="hidden" name="tab" value="compose">
      <input type="hidden" id="source_id" name="source_id" value="#{source.id}">
      <input type="hidden" id="url" name="url" value="#{Helpers.escape_attr(source.url)}">
      <input type="hidden" id="type" name="type" value="#{Helpers.escape_attr(source.type)}">
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
      #{Helpers.error_message(errors, :body_selector)}
      <div class="form-actions">
        <button type="submit" class="btn btn-primary">Save composition</button>
      </div>
    </form>
    #{Scripts.compose_page_script()}
    #{Scripts.compose_script()}
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
        Helpers.option(source, "body_selector") ||
        BodySchema.selector_for_url(source && source.url) ||
        ""

    start_at = params["start_at"] || Helpers.option(source, "start_at") || ""
    skip = params["skip_classes"] || Helpers.skip_classes_text(source)
    content_checked = if fetch == "content", do: "checked", else: ""
    url_checked = if fetch != "content", do: "checked", else: ""

    presets =
      Enum.map_join(Composer.body_presets(), "", fn {label, value} ->
        selected = if value != "" and value == selector, do: " selected", else: ""

        ~s(<option value="#{Helpers.escape_attr(value)}"#{selected}>#{Helpers.escape_html(label)}</option>)
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

    <fieldset class="compose-fieldset">
      <legend>Hashtags</legend>
      #{Fields.excluded_hashtag_fields(params, source, %{})}
    </fieldset>

    <details id="body-regions-details" class="compose-advanced"#{if Helpers.known_body_schema?(selector, source), do: "", else: " open"}
             data-known-selectors="#{Helpers.escape_attr(Enum.join(BodySchema.known_selectors(), ","))}"
             data-url-schema="#{Helpers.escape_attr(to_string(BodySchema.selector_for_url(source && source.url) || ""))}">
      <summary>Which block is the article?</summary>
      <p class="help-text">
        Click the region that looks like the article body. Known sites such as
        Substack are preselected from the article URL.
      </p>
      <input type="hidden" id="body_selector" name="body_selector" value="#{Helpers.escape_attr(selector)}">
      <div id="body-regions" class="body-regions">
        <p class="help-text">Load an article to see candidate regions.</p>
      </div>
    </details>

    <details class="compose-advanced">
      <summary>Start here</summary>
      <p class="help-text">Click the first line that should appear in the body. Everything before it is dropped.</p>
      <input type="hidden" id="start_at" name="start_at" value="#{Helpers.escape_attr(to_string(start_at))}">
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
               value="#{Helpers.escape_attr(selector)}" autocomplete="off">
        <p class="help-text">Leave empty to convert the whole HTML.</p>
      </div>
      <div class="form-group">
        <label for="start_at_text">Start at (XPath)</label>
        <input type="text" id="start_at_text" value="#{Helpers.escape_attr(to_string(start_at))}" autocomplete="off">
      </div>
      <div class="form-group">
        <label for="skip_classes">Skip these CSS classes</label>
        <textarea id="skip_classes" name="skip_classes" rows="3">#{Helpers.escape_html(skip)}</textarea>
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
end
