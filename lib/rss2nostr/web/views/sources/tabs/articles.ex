defmodule Rss2Nostr.Web.Views.Sources.Tabs.Articles do
  @moduledoc false

  alias Rss2Nostr.Nostr.Relays
  alias Rss2Nostr.Posts
  alias Rss2Nostr.Posts.Post
  alias Rss2Nostr.Web.Views.Sources.{Helpers, Scripts}

  def articles_tab(source) do
    posts = Posts.list_posts_for_source(source.id, limit: 100)
    relay_label = Helpers.relay_target_name(Relays.target_for(source))
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
            <td><a href="#{post_preview_href(source, post)}">#{Helpers.escape_html(Helpers.truncate(post.title, 70))}</a></td>
            <td class="article-status"><span class="badge #{Helpers.status_class(post.status)}">#{Post.status_label(post.status)}</span></td>
            <td>#{Helpers.format_datetime(post.published_at)}</td>
            <td class="actions">
              <a href="#{post_preview_href(source, post)}" class="btn btn-small">Preview</a>
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
    #{Scripts.articles_upload_script()}
    """
  end


  def upload_forms(source, posts) do
    return_to = "/sources/#{source.id}?tab=articles"

    posts
    |> Enum.filter(&(&1.status == Post.status_pending_images()))
    |> Enum.map_join("", fn post ->
      """
      <form id="upload-post-#{post.id}" action="/posts/#{post.id}/process" method="POST" hidden>
        <input type="hidden" name="return_to" value="#{Helpers.escape_attr(return_to)}">
      </form>
      """
    end)
  end


  def post_preview_href(source, post) do
    "/posts/#{post.id}?return_to=" <>
      URI.encode_www_form("/sources/#{source.id}?tab=articles")
  end


end
