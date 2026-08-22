defmodule Rss2Nostr.Web.Views.Sources.Show do
  @moduledoc false

  alias Rss2Nostr.Nostr.Relays
  alias Rss2Nostr.Web.Views.Layout
  alias Rss2Nostr.Web.Views.Sources.Helpers
  alias Rss2Nostr.Web.Views.Sources.Tabs.{Articles, Compose, Feed, Publishing}

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
      <h1>#{Helpers.escape_html(source.name)}</h1>
      <div>
        #{Publishing.mode_badge(source, tab)}
        <span class="badge #{if target == :public, do: "badge-public", else: "badge-test"}">
          #{Helpers.relay_target_label(target)}
        </span>
        <form action="/sources/#{source.id}/duplicate" method="POST" style="display:inline">
          <button type="submit" class="btn btn-secondary">Duplicate</button>
        </form>
        <a href="/sources" class="btn btn-secondary">Back to sources</a>
      </div>
    </div>

    #{if saved?, do: "<p class=\"success\">Settings saved.</p>", else: ""}
    #{Helpers.flash_notice(notice, notice_kind)}

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

  def compose(source, opts \\ []), do: show(source, opts)

  defp normalize_tab(tab) when tab in ["feed", "compose", "articles", "publishing"], do: tab
  defp normalize_tab(_), do: "compose"

  defp tab_link(source, name, label, current) do
    class = if name == current, do: "source-tab is-active", else: "source-tab"
    ~s(<a class="#{class}" href="/sources/#{source.id}?tab=#{name}">#{label}</a>)
  end

  defp tab_content(source, "feed", params, errors), do: Feed.feed_tab(source, params, errors)
  defp tab_content(source, "compose", params, errors), do: Compose.compose_tab(source, params, errors)
  defp tab_content(source, "articles", _params, _errors), do: Articles.articles_tab(source)

  defp tab_content(source, "publishing", params, errors),
    do: Publishing.publishing_tab(source, params, errors)
end
