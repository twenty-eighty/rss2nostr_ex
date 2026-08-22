defmodule Rss2Nostr.Web.Views.Sources.Tabs.Feed do
  @moduledoc false

  alias Rss2Nostr.Web.Views.Sources.{Helpers, Language, Scripts}

  def feed_tab(source, params, errors) do
    start_guid = params["start_guid"] || Helpers.option(source, "start_guid") || ""
    start_at = params["start_published_at"] || Helpers.datetime_value(source.publish_after_date)

    """
    <form action="/sources/#{source.id}" method="POST" class="form form-wide">
      <input type="hidden" name="tab" value="feed">
      <div class="form-group">
        <label for="name">Name</label>
        <input type="text" id="name" name="name" required
               value="#{Helpers.escape_attr(params["name"] || source.name)}">
        #{Helpers.error_message(errors, :name)}
      </div>
      <div class="form-group">
        <label for="url">Feed URL</label>
        <input type="text" id="url" name="url" required inputmode="url" autocomplete="url"
               value="#{Helpers.escape_attr(params["url"] || source.url)}">
        #{Helpers.error_message(errors, :url)}
        <p class="help-text">
          One RSS or Atom URL per source. Duplicate the source to follow another
          feed from the same site, then change this URL.
        </p>
      </div>
      <div class="form-group">
        <label for="language">Language</label>
        #{Language.language_select(params["language"] || source.language || "de")}
      </div>
      <div class="form-group">
        <label for="start_article">Start import from</label>
        <input type="hidden" id="start_guid" name="start_guid" value="#{Helpers.escape_attr(to_string(start_guid))}">
        <input type="hidden" id="start_published_at" name="start_published_at" value="#{Helpers.escape_attr(start_at)}">
        <select id="start_article">
          <option value="">Loading articles…</option>
        </select>
        <p class="help-text">
          Changing this only affects future imports. Already imported articles stay.
          Current start: #{Helpers.escape_html(Helpers.start_label(source, start_guid, start_at))}
        </p>
      </div>
      <div class="form-actions">
        <button type="submit" class="btn btn-primary">Save feed settings</button>
      </div>
    </form>
    #{Scripts.feed_start_script()}
    """
  end


end
