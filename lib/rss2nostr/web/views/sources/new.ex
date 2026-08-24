defmodule Rss2Nostr.Web.Views.Sources.New do
  @moduledoc false

  alias Rss2Nostr.Web.Views.{Layout, Sources.Fields, Sources.Language, Sources.Scripts}
  alias Rss2Nostr.Web.Views.Sources.Helpers

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
                 value="#{Helpers.escape_attr(params["website"])}">
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
          #{Helpers.error_message(errors, :url)}
        </div>

        <input type="hidden" id="url" name="url" value="#{Helpers.escape_attr(params["url"])}">
        <input type="hidden" id="type" name="type" value="#{Helpers.escape_attr(params["type"] || "atom")}">
        <input type="hidden" id="start_guid" name="start_guid" value="#{Helpers.escape_attr(params["start_guid"])}">
        <input type="hidden" id="start_published_at" name="start_published_at" value="#{Helpers.escape_attr(params["start_published_at"])}">

        <div class="form-group">
          <label for="name">Name</label>
          <input type="text" id="name" name="name" required placeholder="e.g., Heise News"
                 value="#{Helpers.escape_attr(params["name"])}">
          #{Helpers.error_message(errors, :name)}
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
          #{Language.language_select(params["language"] || "de")}
        </div>

        #{Fields.publish_as_fields(params, nil, errors)}
        #{Fields.fixed_hashtag_fields(params, nil, errors)}
        #{Fields.excluded_hashtag_fields(params, nil, errors)}
      </div>

      <div class="form-actions">
        <button type="submit" class="btn btn-primary" id="submit-source" #{if params["url"] in [nil, ""], do: "disabled", else: ""}>Add Source</button>
        <a href="/sources" class="btn btn-secondary">Cancel</a>
      </div>
    </form>
    #{Scripts.discover_script()}
    """

    Layout.render("Add Source", content, active_nav: "sources", wide: true)
  end
end
