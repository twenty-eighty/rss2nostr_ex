defmodule Rss2Nostr.Web.Views.Posts do
  @moduledoc """
  Views for post management.
  """

  alias Rss2Nostr.Web.Views.Layout
  alias Rss2Nostr.Web.Views.Sources, as: SourceViews
  alias Rss2Nostr.Posts
  alias Rss2Nostr.Posts.Post
  alias Rss2Nostr.Processing.{Markdown, Processor}
  alias Rss2Nostr.Sources
  alias Rss2Nostr.Sources.Source
  alias Rss2Nostr.Nostr.{Blossom, Event, Publisher, Relays, Signer}

  @per_page 20

  def index(opts \\ []) do
    status_filter = blank_to_nil(Keyword.get(opts, :status))
    source_id = parse_source_id(Keyword.get(opts, :source_id))
    q = blank_to_nil(trim_filter(Keyword.get(opts, :q)))
    page = Keyword.get(opts, :page, 1)
    notice = Keyword.get(opts, :notice)
    notice_kind = Keyword.get(opts, :notice_kind)
    offset = (page - 1) * @per_page

    posts =
      Posts.list_posts(
        limit: @per_page,
        offset: offset,
        status: status_filter,
        source_id: source_id,
        q: q
      )

    sources = Enum.sort_by(Sources.list_sources(), & &1.name)
    return_to = posts_path(status: status_filter, source_id: source_id, q: q, page: page)
    selectable_ids = selectable_post_ids(status_filter, source_id, q)
    publishable_ids = MapSet.new(publishable_post_ids(status_filter, source_id, q))
    page_ids = MapSet.new(Enum.map(posts, & &1.id))
    extra_ids = Enum.reject(selectable_ids, &MapSet.member?(page_ids, &1))
    selectable? = selectable_ids != []
    publishable? = not MapSet.equal?(publishable_ids, MapSet.new())

    rows =
      if Enum.empty?(posts) do
        "<tr><td colspan=\"6\" class=\"empty-state\">No posts found.</td></tr>"
      else
        Enum.map_join(posts, "", fn post ->
          status_class = status_to_class(post.status)
          status_label = Post.status_label(post.status)

          """
          <tr>
            <td class="article-select">
              #{if reprocessable?(post) do
            ~s(<input type="checkbox" name="post_ids[]" value="#{post.id}" data-publishable="#{publishable?(post)}">)
          else
            ""
          end}
            </td>
            <td><a href="#{post_show_href(post.id, return_to)}">#{escape_html(truncate(post.title, 60))}</a></td>
            <td><span class="badge #{status_class}">#{status_label}</span></td>
            <td>#{escape_html(truncate(post.source_url, 40))}</td>
            <td>#{format_datetime(post.published_at)}</td>
            <td class="actions">
              #{action_buttons(post)}
            </td>
          </tr>
          """
        end)
      end

    content = """
    <div class="page-header">
      <h1>Posts</h1>
    </div>

    #{flash_notice(notice, notice_kind)}

    <div class="filter-bar">
      <a href="#{posts_path(status: nil, source_id: source_id, q: q)}" class="btn btn-small #{if is_nil(status_filter), do: "btn-active"}">All</a>
      <a href="#{posts_path(status: "0", source_id: source_id, q: q)}" class="btn btn-small #{if status_filter == "0", do: "btn-active"}">New</a>
      <a href="#{posts_path(status: "9", source_id: source_id, q: q)}" class="btn btn-small #{if status_filter == "9", do: "btn-active"}">Pending images</a>
      <a href="#{posts_path(status: "2", source_id: source_id, q: q)}" class="btn btn-small #{if status_filter == "2", do: "btn-active"}">Staging</a>
      <a href="#{posts_path(status: "6", source_id: source_id, q: q)}" class="btn btn-small #{if status_filter == "6", do: "btn-active"}">Published</a>
      <form method="get" action="/posts" class="filter-source">
        #{if status_filter, do: ~s(<input type="hidden" name="status" value="#{escape_attr(to_string(status_filter))}">), else: ""}
        <label for="source_id">Source</label>
        <select id="source_id" name="source_id" onchange="this.form.submit()">
          <option value="">All sources</option>
          #{source_options(sources, source_id)}
        </select>
        <label for="q">Contains</label>
        <input type="search" id="q" name="q" value="#{escape_attr(q)}" placeholder="Filter articles">
        <button type="submit" class="btn btn-small">Apply</button>
      </form>
    </div>

    #{post_action_forms(posts, return_to)}
    <div class="article-toolbar">
      <button type="submit" class="btn btn-primary" form="posts-bulk-form"
              #{unless publishable?, do: "disabled"}>Publish selected</button>
      <button type="submit" class="btn btn-secondary" form="posts-bulk-form"
              formaction="/posts/reprocess-selected"
              #{unless selectable?, do: "disabled"}>Reprocess selected</button>
    </div>
    <p class="help-text">Select all includes matching articles, not only this page. Staging articles can be published; pending-images articles can be reprocessed. Relays come from each source: drafts use the draft list, articles use public or test from the source flag.</p>
    <form id="posts-bulk-form" action="/posts/publish-selected" method="POST">
      <input type="hidden" name="return_to" value="#{escape_attr(return_to)}">
      #{Enum.map_join(extra_ids, "", fn id ->
        ~s(<input type="checkbox" name="post_ids[]" value="#{id}" data-publishable="#{MapSet.member?(publishable_ids, id)}" hidden>)
      end)}
    <table class="table">
      <thead>
        <tr>
          <th class="article-select">
            <input type="checkbox" id="select-all-posts" aria-label="Select all filtered articles"
                   #{unless selectable?, do: "disabled"}>
          </th>
          <th>Title</th>
          <th>Status</th>
          <th>Source</th>
          <th>Published</th>
          <th>Actions</th>
        </tr>
      </thead>
      <tbody>
        #{rows}
      </tbody>
    </table>
    </form>
    #{posts_select_all_script()}

    <div class="pagination">
      #{if page > 1, do: ~s(<a href="#{posts_path(status: status_filter, source_id: source_id, q: q, page: page - 1)}" class="btn btn-small">&larr; Previous</a>)}
      <span>Page #{page}</span>
      #{if length(posts) == @per_page, do: ~s(<a href="#{posts_path(status: status_filter, source_id: source_id, q: q, page: page + 1)}" class="btn btn-small">Next &rarr;</a>)}
    </div>
    """

    Layout.render("Posts", content, active_nav: "posts")
  end

  def show(id, opts \\ []) do
    notice = Keyword.get(opts, :notice)

    case Posts.get_post(String.to_integer(id), preload: [:source, :images]) do
      nil ->
        Layout.render(
          "Post Not Found",
          "<h1>Post Not Found</h1><p>The requested post does not exist.</p>",
          active_nav: "posts"
        )

      post ->
        post = Processor.finish_if_images_ready(post)
        status_class = status_to_class(post.status)
        status_label = Post.status_label(post.status)
        editable? = post.status in [Post.status_processed(), Post.status_published()]
        back = back_path(post, Keyword.get(opts, :return_to))

        content = """
        <div class="page-header">
          <h1>#{escape_html(post.title)}</h1>
          <span class="badge #{status_class}">#{status_label}</span>
        </div>

        #{flash_notice(notice, Keyword.get(opts, :notice_kind))}

        <div class="post-meta">
          #{if post.source_url, do: "<p><strong>Source:</strong> <a href=\"#{escape_html(post.source_url)}\" target=\"_blank\">#{escape_html(truncate(post.source_url, 60))}</a></p>"}
          #{if post.published_at, do: "<p><strong>Published:</strong> #{format_datetime(post.published_at)}</p>"}
          #{staging_hold_note(post)}
          #{if post.event_id, do: "<p><strong>Event ID:</strong> <code>#{post.event_id}</code></p>"}
          #{if post.nostr_address, do: "<p><strong>Nostr Address:</strong> <code>#{truncate(post.nostr_address, 60)}</code></p>"}
          <p><strong>Relays:</strong> #{audience_label(post)}</p>
          #{publish_notes(post)}
        </div>

        <div class="post-actions">
          #{show_actions(post, back)}
          <a href="#{escape_attr(back)}" class="btn btn-secondary">Back to List</a>
        </div>

        <div class="compose-tabs" role="tablist" style="margin: 1.25rem 0 1rem">
          <button type="button" class="compose-tab is-active" data-post-tab="article" role="tab" aria-selected="true">Article</button>
          <button type="button" class="compose-tab" data-post-tab="preview" role="tab" aria-selected="false">Preview</button>
          <button type="button" class="compose-tab" data-post-tab="event" role="tab" aria-selected="false">Event</button>
        </div>

        <div id="post-article-tab">
          #{if editable?, do: editor_form(post, back), else: read_only_article(post)}
        </div>

        <div id="post-preview-tab" hidden>
          #{article_preview(post)}
        </div>

        <div id="post-event-tab" hidden>
          <p class="help-text">
            #{event_tab_intro(post)}
            <code>id</code> and <code>sig</code> are added when publishing;
            <code>created_at</code> is a preview timestamp.
            Changing the title does not change the <code>d</code> tag.
          </p>
          #{event_preview(post)}
        </div>
        #{post_tab_script()}

        #{images_section(post)}

        #{if post.source_html do
          """
          <details class="post-source">
            <summary>Original HTML</summary>
            <pre>#{escape_html(truncate(post.source_html, 2000))}</pre>
          </details>
          """
        end}
        """

        Layout.render(post.title, content, active_nav: "posts")
    end
  end

  defp show_actions(post, back) do
    audience = relay_target_name(post)
    return_to = return_to_hidden(back)

    cond do
      post.status in [Post.status_new(), Post.status_pending_images()] ->
        """
        <form action="/posts/#{post.id}/process" method="POST" style="display:inline">
          #{return_to}
          <button type="submit" class="btn btn-primary">#{if post.status == Post.status_pending_images(), do: "Upload images", else: "Process"}</button>
        </form>
        #{if post.status == Post.status_pending_images() do
          """
          <form action="/posts/#{post.id}/reprocess" method="POST" style="display:inline">
            #{return_to}
            <button type="submit" class="btn btn-secondary">Reprocess</button>
          </form>
          """
        end}
        """

      post.status == Post.status_processed() ->
        """
        <form action="/posts/#{post.id}/publish" method="POST" style="display:inline">
          #{return_to}
          <button type="submit" class="btn btn-primary">Publish to #{audience} relays</button>
        </form>
        <form action="/posts/#{post.id}/reprocess" method="POST" style="display:inline">
          #{return_to}
          <button type="submit" class="btn btn-secondary">Reprocess</button>
        </form>
        """

      post.status == Post.status_published() ->
        """
        <form action="/posts/#{post.id}/publish" method="POST" style="display:inline">
          #{return_to}
          <button type="submit" class="btn btn-primary">Republish to #{audience} relays</button>
        </form>
        <form action="/posts/#{post.id}/revise" method="POST" style="display:inline">
          #{return_to}
          <button type="submit" class="btn btn-secondary">Revise</button>
        </form>
        """

      true ->
        ""
    end
  end

  defp editor_form(post, back) do
    hashtags = Enum.join(published_hashtags(post), ", ")

    """
    <form action="/posts/#{post.id}" method="POST" class="form form-wide post-editor">
      #{return_to_hidden(back)}
      <div class="form-group">
        <label for="title">Title</label>
        <input type="text" id="title" name="title" value="#{escape_attr(post.title)}">
      </div>
      <div class="form-group">
        <label for="summary">Summary</label>
        <textarea id="summary" name="summary" rows="3">#{escape_html(post.summary)}</textarea>
      </div>
      <div class="form-group">
        <label for="hashtags">Hashtags</label>
        <input type="text" id="hashtags" name="hashtags" value="#{escape_attr(hashtags)}" placeholder="comma-separated">
        <p class="help-text">#{hashtag_help(post)}</p>
      </div>
      <div class="form-group">
        <label for="language">Language</label>
        #{SourceViews.language_select(post.language || "de")}
      </div>
      <div class="form-group">
        <label for="content">Markdown</label>
        <textarea id="content" name="content" class="post-editor-markdown">#{escape_html(post.content)}</textarea>
      </div>
      <div class="form-actions">
        <button type="submit" class="btn btn-primary">Save</button>
      </div>
    </form>
    """
  end

  defp read_only_article(post) do
    """
    #{featured_image(post)}
    <div class="post-content">
      <h3>Content</h3>
      <div class="content-preview">
        #{if post.content, do: "<pre>#{escape_html(post.content)}</pre>", else: "<p class=\"empty-state\">No content yet. Process the post first.</p>"}
      </div>
    </div>
    """
  end

  defp article_preview(post) do
    rendered =
      if present?(post.content) do
        ~s(<div class="compose-preview-rendered">#{Markdown.to_html(post.content)}</div>)
      else
        ~s(<p class="empty-state">No content yet.</p>)
      end

    """
    #{featured_image(post)}
    #{hashtag_preview(post)}
    #{rendered}
    """
  end

  defp published_hashtags(post) do
    Event.merge_hashtags(
      post.categories,
      source_hashtags(post, :fixed_hashtags),
      source_hashtags(post, :excluded_hashtags)
    )
  end

  defp omitted_hashtags(post) do
    skip = MapSet.new(Event.normalize_hashtags(source_hashtags(post, :excluded_hashtags)))

    (post.categories || [])
    |> Enum.filter(fn tag ->
      Enum.any?(Event.normalize_hashtags([tag]), &MapSet.member?(skip, &1))
    end)
  end

  defp source_hashtags(%{source: %Source{} = source}, field), do: Map.get(source, field) || []
  defp source_hashtags(_, _), do: []

  defp hashtag_help(post) do
    case omitted_hashtags(post) do
      [] ->
        "Published as <code>t</code> tags."

      omitted ->
        "Published as <code>t</code> tags. Omitted from the event: #{escape_html(Enum.join(omitted, ", "))}."
    end
  end

  defp hashtag_preview(post) do
    case published_hashtags(post) do
      [] ->
        ~s(<p class="compose-preview-meta"><strong>Hashtags:</strong> none</p>)

      tags ->
        text = Enum.map_join(tags, ", ", &("##{&1}"))
        ~s(<p class="compose-preview-meta"><strong>Hashtags:</strong> #{escape_html(text)}</p>)
    end
  end

  defp featured_image(post) do
    if present?(post.image) do
      """
      <div class="post-image">
        <h3>Featured Image</h3>
        <img src="#{escape_html(post.image)}" alt="Featured image" style="max-width: 400px;">
      </div>
      """
    else
      ""
    end
  end

  defp staging_hold_note(post) do
    source = post.source

    cond do
      post.status != Post.status_processed() ->
        ""

      not match?(%Source{}, source) ->
        ""

      true ->
        hold = source.staging_hold_minutes || 0
        staged = format_datetime(post.staged_at)

        detail =
          cond do
            not Source.automated?(source) ->
              "Waiting for manual publish."

            hold <= 0 ->
              "Ready to auto-publish."

            rem(hold, 60) == 0 ->
              "Auto-publishes #{div(hold, 60)}h after staging."

            true ->
              "Auto-publishes #{hold} minutes after staging."
          end

        "<p><strong>Staged:</strong> #{staged} — #{escape_html(detail)}</p>"
    end
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: false

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

  defp publish_notes(%{last_error: error} = post) when is_binary(error) and error != "" do
    if post.status == Post.status_published() do
      ~s(<p class="warning"><strong>Publish notes:</strong> #{escape_html(error)}</p>)
    else
      ~s(<p class="error"><strong>Last error:</strong> #{escape_html(error)}</p>)
    end
  end

  defp publish_notes(_), do: ""

  defp images_section(post) do
    images = post.images || []

    cond do
      images == [] and (is_nil(post.image) or post.image == "") ->
        ""

      true ->
        rows =
          if images == [] do
            featured_row(post.image)
          else
            Enum.map_join(images, "", &image_row/1)
          end

        """
        <div class="post-content" style="margin-top: 1.5rem">
          <h3>Images and audio</h3>
          <p class="help-text">
            Staging articles must have the featured image and every referenced image or audio file uploaded.
          </p>
          <table class="table">
            <thead>
              <tr>
                <th>Original</th>
                <th>Uploaded</th>
                <th>imeta</th>
              </tr>
            </thead>
            <tbody>#{rows}</tbody>
          </table>
        </div>
        """
    end
  end

  defp featured_row(url) do
    uploaded = if Blossom.already_hosted?(url), do: url, else: nil
    image_row(%{original_url: url, uploaded_url: uploaded})
  end

  defp image_row(image) do
    uploaded = Map.get(image, :uploaded_url)
    imeta = imeta_summary(image)

    """
    <tr>
      <td><code class="url">#{escape_html(truncate(image.original_url, 80))}</code></td>
      <td>#{if uploaded, do: "<code class=\"url\">#{escape_html(truncate(uploaded, 80))}</code>", else: "<span class=\"badge badge-pending-images\">pending</span>"}</td>
      <td>#{if imeta != "", do: "<code>#{escape_html(imeta)}</code>", else: "—"}</td>
    </tr>
    """
  end

  defp imeta_summary(image) do
    [Map.get(image, :mime_type), Map.get(image, :dim), Map.get(image, :file_size) && "#{image.file_size} B"]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" · ")
  end

  defp event_tab_intro(post) do
    cond do
      Signer.encrypted_draft?(post.source) ->
        """
        Inner article <code>EVENT</code> as it will be NIP-44-encrypted into a
        kind 31234 wrap when published. Long drafts are split so each
        published <code>["EVENT", wrap]</code> stays under 65535 bytes.
        """

      Signer.plain_draft?(post.source) ->
        """
        Kind 30024 <code>EVENT</code> signed by the app key when published.
        Long drafts are split so each published event stays under 65535 bytes.
        """

      true ->
        """
        Kind 30023 <code>EVENT</code> as it will be signed and published.
        Long articles are split so each published event stays under 65535 bytes.
        """
    end
  end

  defp event_preview(post) do
    preview = Publisher.preview_event(post)
    relays = Enum.map_join(preview.relays, "\n", & &1)
    parts = preview.parts
    total = length(parts)

    note =
      cond do
        preview.draft and total > 1 ->
          """
          <p class="help-text">
            This article will be published as #{total} NIP-37 drafts so each
            published wrap stays within 65535 bytes.
          </p>
          """

        preview.draft ->
          """
          <p class="help-text">
            This inner article is NIP-44-encrypted into a kind 31234 wrap when published.
          </p>
          """

        preview.plain_draft ->
          """
          <p class="help-text">
            Published as kind 30024, signed by the app key.
          </p>
          """

        true ->
          ""
      end

    part_blocks =
      parts
      |> Enum.with_index(1)
      |> Enum.map_join("", fn {event, index} ->
        heading =
          if total > 1 do
            "<p><strong>Part #{index}/#{total}</strong></p>\n"
          else
            "<p><strong>Message</strong></p>\n"
          end

        json = Jason.encode!(["EVENT", event], pretty: true)
        heading <> ~s(<pre class="compose-preview">#{escape_html(json)}</pre>\n)
      end)

    """
    <p><strong>Relays</strong></p>
    <pre class="compose-preview">#{escape_html(if relays == "", do: "(none configured)", else: relays)}</pre>
    #{note}
    #{part_blocks}
    """
  end

  defp post_tab_script do
    """
    <script>
    (function () {
      const tabs = document.querySelectorAll("[data-post-tab]");
      const panels = {
        article: document.getElementById("post-article-tab"),
        preview: document.getElementById("post-preview-tab"),
        event: document.getElementById("post-event-tab")
      };
      if (!tabs.length || !panels.article || !panels.preview || !panels.event) return;
      tabs.forEach(function (tab) {
        tab.addEventListener("click", function () {
          const name = tab.getAttribute("data-post-tab");
          Object.keys(panels).forEach(function (key) {
            panels[key].hidden = key !== name;
          });
          tabs.forEach(function (other) {
            const selected = other === tab;
            other.classList.toggle("is-active", selected);
            other.setAttribute("aria-selected", selected ? "true" : "false");
          });
        });
      });
    })();
    </script>
    """
  end

  defp selectable_post_ids(status_filter, source_id, q) do
    cond do
      status_filter in [nil, ""] ->
        post_ids_for(Post.status_processed(), source_id, q) ++
          post_ids_for(Post.status_pending_images(), source_id, q)

      status_filter == "2" ->
        post_ids_for(Post.status_processed(), source_id, q)

      status_filter == "9" ->
        post_ids_for(Post.status_pending_images(), source_id, q)

      true ->
        []
    end
  end

  defp publishable_post_ids(status_filter, source_id, q) do
    if status_filter in [nil, "", "2"] do
      post_ids_for(Post.status_processed(), source_id, q)
    else
      []
    end
  end

  defp post_ids_for(status, source_id, q) do
    Posts.list_posts(status: status, source_id: source_id, q: q, limit: 5_000)
    |> Enum.map(& &1.id)
  end

  defp reprocessable?(post) do
    post.status in [Post.status_processed(), Post.status_pending_images()]
  end

  defp publishable?(post), do: post.status == Post.status_processed()

  defp posts_select_all_script do
    """
    <script>
    (function () {
      const selectAll = document.getElementById("select-all-posts");

      function selectableBoxes() {
        return document.querySelectorAll("#posts-bulk-form input[name='post_ids[]']");
      }

      function syncSelectAll() {
        if (!selectAll) return;
        const boxes = Array.from(selectableBoxes());
        selectAll.disabled = boxes.length === 0;
        const checked = boxes.filter(function (box) { return box.checked; }).length;
        selectAll.checked = boxes.length > 0 && checked === boxes.length;
        selectAll.indeterminate = checked > 0 && checked < boxes.length;
      }

      if (selectAll) {
        selectAll.addEventListener("change", function () {
          selectableBoxes().forEach(function (box) {
            box.checked = selectAll.checked;
          });
          selectAll.indeterminate = false;
        });
        document.addEventListener("change", function (event) {
          if (event.target && event.target.name === "post_ids[]") syncSelectAll();
        });
      }
    })();
    </script>
    """
  end

  defp post_action_forms(posts, return_to) do
    Enum.map_join(posts, "", fn post ->
      case post.status do
        status when status in [0, 9] ->
          """
          <form id="post-action-#{post.id}" action="/posts/#{post.id}/process" method="POST" hidden>
            <input type="hidden" name="return_to" value="#{escape_attr(return_to)}">
          </form>
          """

        2 ->
          """
          <form id="post-action-#{post.id}" action="/posts/#{post.id}/publish" method="POST" hidden>
            <input type="hidden" name="return_to" value="#{escape_attr(return_to)}">
          </form>
          """

        _ ->
          ""
      end
    end)
  end

  defp action_buttons(post) do
    case post.status do
      0 ->
        ~s(<button type="submit" class="btn btn-small" form="post-action-#{post.id}">Process</button>)

      9 ->
        ~s(<button type="submit" class="btn btn-small" form="post-action-#{post.id}">Upload images</button>)

      2 ->
        ~s(<button type="submit" class="btn btn-small" form="post-action-#{post.id}">Export</button>)

      _ ->
        ""
    end
  end

  defp audience_label(post) do
    case Relays.target_for(post) do
      :draft -> "<span class=\"badge badge-test\">Draft</span>"
      :public -> "<span class=\"badge badge-public\">Public</span>"
      _ -> "<span class=\"badge badge-test\">Test</span>"
    end
  end

  defp relay_target_name(post) do
    case Relays.target_for(post) do
      :draft -> "draft"
      :public -> "public"
      _ -> "test"
    end
  end

  defp post_show_href(id, return_to) do
    "/posts/#{id}?return_to=" <> URI.encode_www_form(return_to)
  end

  defp back_path(post, return_to) do
    cond do
      internal_path?(return_to) -> return_to
      source_id = source_id_of(post) -> "/sources/#{source_id}?tab=articles"
      true -> "/posts"
    end
  end

  defp source_id_of(%{source: %Source{id: id}}), do: id
  defp source_id_of(%{source_id: id}) when is_integer(id), do: id
  defp source_id_of(_), do: nil

  defp return_to_hidden(path) do
    if internal_path?(path) do
      ~s(<input type="hidden" name="return_to" value="#{escape_attr(path)}">)
    else
      ""
    end
  end

  defp internal_path?("//" <> _), do: false
  defp internal_path?("/" <> _), do: true
  defp internal_path?(_), do: false

  defp posts_path(params) do
    query =
      params
      |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
      |> Enum.map(fn {key, value} -> {to_string(key), to_string(value)} end)
      |> URI.encode_query()

    case query do
      "" -> "/posts"
      encoded -> "/posts?" <> encoded
    end
  end

  defp source_options(sources, selected_id) do
    Enum.map_join(sources, "", fn source ->
      selected = if source.id == selected_id, do: " selected", else: ""
      ~s(<option value="#{source.id}"#{selected}>#{escape_html(source.name)}</option>)
    end)
  end

  defp parse_source_id(nil), do: nil
  defp parse_source_id(""), do: nil
  defp parse_source_id(id) when is_integer(id), do: id

  defp parse_source_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp trim_filter(nil), do: nil
  defp trim_filter(value) when is_binary(value), do: String.trim(value)
  defp trim_filter(value), do: value

  defp escape_attr(nil), do: ""

  defp escape_attr(str) when is_binary(str) do
    str
    |> escape_html()
    |> String.replace("\"", "&quot;")
  end

  defp status_to_class(status) do
    case status do
      0 -> "badge-new"
      1 -> "badge-processing"
      2 -> "badge-processed"
      6 -> "badge-published"
      9 -> "badge-pending-images"
      _ -> "badge-error"
    end
  end

  defp escape_html(str) when is_binary(str) do
    str
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp escape_html(nil), do: ""

  defp truncate(str, max) when is_binary(str) do
    if String.length(str) > max do
      String.slice(str, 0, max) <> "..."
    else
      str
    end
  end

  defp truncate(nil, _max), do: ""

  defp format_datetime(nil), do: "-"

  defp format_datetime(dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  end
end
