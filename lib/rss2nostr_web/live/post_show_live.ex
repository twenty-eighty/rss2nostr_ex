defmodule Rss2NostrWeb.PostShowLive do
  @moduledoc false

  use Rss2NostrWeb, :live_view

  alias Rss2Nostr.Nostr.{Blossom, Event, Publisher, Relays, Signer}
  alias Rss2Nostr.Posts
  alias Rss2Nostr.Posts.Post
  alias Rss2Nostr.Processing.{Markdown, Processor}
  alias Rss2Nostr.Sources.Source
  alias Rss2Nostr.Web.API.Posts, as: PostsAPI

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case fetch_post(id) do
      {:ok, post} ->
        {:ok,
         socket
         |> assign(:active_nav, "posts")
         |> assign(:wide, true)
         |> assign(:tab, "article")
         |> assign(:busy, false)
         |> assign(:return_to, "/posts")
         |> assign_post(post)}

      :error ->
        {:ok,
         socket
         |> assign(:post, nil)
         |> put_flash(:error, "Post not found")
         |> redirect(to: "/posts")}
    end
  end

  @impl true
  def handle_params(_params, _uri, %{assigns: %{post: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_params(params, _uri, socket) do
    back = back_path(socket.assigns.post, params["return_to"])

    {:noreply,
     socket
     |> assign(:return_to, back)
     |> assign(:page_title, socket.assigns.post.title || "Post")}
  end

  @impl true
  def handle_event("set_tab", %{"tab" => tab}, socket)
      when tab in ["article", "preview", "event"] do
    {:noreply, assign(socket, :tab, tab)}
  end

  def handle_event("save", params, socket) do
    case PostsAPI.update(to_string(socket.assigns.post.id), params) do
      {:ok, _post} ->
        {:ok, post} = fetch_post(socket.assigns.post.id)

        {:noreply,
         socket
         |> put_flash(:info, "Saved")
         |> assign_post(post)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, format_update_error(reason))}
    end
  end

  def handle_event("process", _params, socket) do
    run_action(socket, :process, fn -> PostsAPI.process(to_string(socket.assigns.post.id)) end)
  end

  def handle_event("reprocess", _params, socket) do
    run_action(socket, :reprocess, fn ->
      PostsAPI.reprocess(to_string(socket.assigns.post.id))
    end)
  end

  def handle_event("revise", _params, socket) do
    run_action(socket, :revise, fn -> PostsAPI.revise(to_string(socket.assigns.post.id)) end, "Reconverted from HTML and moved to staging")
  end

  def handle_event("publish", _params, socket) do
    id = to_string(socket.assigns.post.id)

    {:noreply,
     socket
     |> assign(:busy, true)
     |> start_async(:publish, fn -> PostsAPI.publish(id) end)}
  end

  @impl true
  def handle_async(:action, {:ok, {:ok, _post}}, socket) do
    {:ok, post} = fetch_post(socket.assigns.post.id)
    message = socket.assigns[:action_notice] || "Done"

    {:noreply,
     socket
     |> assign(:busy, false)
     |> assign(:action_notice, nil)
     |> put_flash(:info, message)
     |> assign_post(post)}
  end

  def handle_async(:action, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:busy, false)
     |> put_flash(:error, format_update_error(reason))}
  end

  def handle_async(:action, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:busy, false)
     |> put_flash(:error, Exception.format_exit(reason))}
  end

  def handle_async(:publish, {:ok, {:ok, result}}, socket) do
    {:ok, post} = fetch_post(socket.assigns.post.id)
    {kind, message} = publish_notice(normalize_one_publish(result))

    {:noreply,
     socket
     |> assign(:busy, false)
     |> put_flash(kind, message)
     |> assign_post(post)}
  end

  def handle_async(:publish, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:busy, false)
     |> put_flash(:error, format_update_error(reason))}
  end

  def handle_async(:publish, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:busy, false)
     |> put_flash(:error, Exception.format_exit(reason))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="page-header">
      <h1>{@post.title}</h1>
      <.status_badge status={@post.status} />
    </div>

    <div class="post-meta">
      <p :if={@post.source_url}>
        <strong>Source:</strong>
        <a href={@post.source_url} target="_blank">{truncate(@post.source_url, 60)}</a>
      </p>
      <p :if={@post.published_at}>
        <strong>Published:</strong> {format_datetime(@post.published_at)}
      </p>
      {raw(staging_hold_note(@post))}
      <p :if={@post.event_id}><strong>Event ID:</strong> <code>{@post.event_id}</code></p>
      <p :if={@post.nostr_address}>
        <strong>Nostr Address:</strong> <code>{truncate(@post.nostr_address, 60)}</code>
      </p>
      <p>
        <strong>Relays:</strong>
        <span class={"badge #{relay_badge_class(Relays.target_for(@post))}"}>
          {relay_target_label(Relays.target_for(@post))}
        </span>
      </p>
      <p :if={@post.last_error not in [nil, ""]} class={if @post.status == Post.status_published(), do: "warning", else: "error"}>
        <strong>{if @post.status == Post.status_published(), do: "Publish notes:", else: "Last error:"}</strong>
        {@post.last_error}
      </p>
    </div>

    <div class="post-actions">
      <.show_actions post={@post} busy={@busy} />
      <a href={@return_to} class="btn btn-secondary">Back to List</a>
    </div>

    <div class="compose-tabs" role="tablist" style="margin: 1.25rem 0 1rem">
      <button
        type="button"
        class={["compose-tab", @tab == "article" && "is-active"]}
        data-post-tab="article"
        phx-click="set_tab"
        phx-value-tab="article"
      >
        Article
      </button>
      <button
        type="button"
        class={["compose-tab", @tab == "preview" && "is-active"]}
        data-post-tab="preview"
        phx-click="set_tab"
        phx-value-tab="preview"
      >
        Preview
      </button>
      <button
        type="button"
        class={["compose-tab", @tab == "event" && "is-active"]}
        data-post-tab="event"
        phx-click="set_tab"
        phx-value-tab="event"
      >
        Event
      </button>
    </div>

    <div id="post-article-tab" hidden={@tab != "article"}>
      <%= if @editable? do %>
        <form phx-submit="save" class="form form-wide post-editor">
          <input type="hidden" name="return_to" value={@return_to} />
          <div class="form-group">
            <label for="title">Title</label>
            <input type="text" id="title" name="title" value={@editor["title"]} />
          </div>
          <div class="form-group">
            <label for="summary">Summary</label>
            <textarea id="summary" name="summary" rows="3">{@editor["summary"]}</textarea>
          </div>
          <div class="form-group">
            <label for="hashtags">Hashtags</label>
            <input
              type="text"
              id="hashtags"
              name="hashtags"
              value={@editor["hashtags"]}
              placeholder="comma-separated"
            />
            <p class="help-text">{raw(hashtag_help(@post))}</p>
          </div>
          <div class="form-group">
            <label for="language">Language</label>
            <select id="language" name="language">
              <option
                :for={{code, label} <- language_options(@editor["language"])}
                value={code}
                selected={code == @editor["language"]}
              >
                {label}
              </option>
            </select>
          </div>
          <div class="form-group">
            <label for="content">Markdown</label>
            <textarea id="content" name="content" class="post-editor-markdown">{@editor["content"]}</textarea>
          </div>
          <div class="form-actions">
            <button type="submit" class="btn btn-primary" disabled={@busy}>Save</button>
          </div>
        </form>
      <% else %>
        <.featured_image post={@post} />
        <div class="post-content">
          <h3>Content</h3>
          <div class="content-preview">
            <%= if present?(@post.content) do %>
              <pre>{@post.content}</pre>
            <% else %>
              <p class="empty-state">No content yet. Process the post first.</p>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>

    <div id="post-preview-tab" hidden={@tab != "preview"}>
      <.featured_image post={@post} />
      <p class="compose-preview-meta">
        <strong>Hashtags:</strong>
        {hashtag_preview_text(@post)}
      </p>
      <%= if present?(@post.content) do %>
        <div class="compose-preview-rendered">{raw(Markdown.to_html(@post.content))}</div>
      <% else %>
        <p class="empty-state">No content yet.</p>
      <% end %>
    </div>

    <div id="post-event-tab" hidden={@tab != "event"}>
      <p class="help-text">
        {raw(event_tab_intro(@post))}
        <code>id</code> and <code>sig</code> are added when publishing;
        <code>created_at</code> is a preview timestamp.
        Changing the title does not change the <code>d</code> tag.
      </p>
      {raw(@event_html)}
    </div>

    <.images_section post={@post} />

    <details :if={@post.source_html} class="post-source">
      <summary>Original HTML</summary>
      <pre>{truncate(@post.source_html, 2000)}</pre>
    </details>
    """
  end

  defp show_actions(assigns) do
    audience = relay_target_name(Relays.target_for(assigns.post))
    status = assigns.post.status

    assigns =
      assigns
      |> assign(:audience, audience)
      |> assign(:new?, status == Post.status_new())
      |> assign(:pending?, status == Post.status_pending_images())
      |> assign(:staging?, status == Post.status_processed())
      |> assign(:published?, status == Post.status_published())

    ~H"""
    <button
      :if={@new?}
      type="button"
      class="btn btn-primary"
      phx-click="process"
      disabled={@busy}
    >
      Process
    </button>
    <button
      :if={@pending?}
      type="button"
      class="btn btn-primary"
      phx-click="process"
      disabled={@busy}
    >
      Upload images
    </button>
    <button
      :if={@pending?}
      type="button"
      class="btn btn-secondary"
      phx-click="reprocess"
      disabled={@busy}
    >
      Reprocess
    </button>
    <button
      :if={@staging?}
      type="button"
      class="btn btn-primary"
      phx-click="publish"
      disabled={@busy}
    >
      Publish to {@audience} relays
    </button>
    <button
      :if={@staging?}
      type="button"
      class="btn btn-secondary"
      phx-click="reprocess"
      disabled={@busy}
    >
      Reprocess
    </button>
    <button
      :if={@published?}
      type="button"
      class="btn btn-primary"
      phx-click="publish"
      disabled={@busy}
    >
      Republish to {@audience} relays
    </button>
    <button
      :if={@published?}
      type="button"
      class="btn btn-secondary"
      phx-click="revise"
      disabled={@busy}
    >
      Revise
    </button>
    """
  end

  defp featured_image(assigns) do
    ~H"""
    <div :if={present?(@post.image)} class="post-image">
      <h3>Featured Image</h3>
      <img src={@post.image} alt="Featured image" style="max-width: 400px;" />
    </div>
    """
  end

  defp images_section(assigns) do
    images = assigns.post.images || []
    show? = images != [] or present?(assigns.post.image)
    rows = if images == [], do: [%{original_url: assigns.post.image, uploaded_url: uploaded_url(assigns.post.image)}], else: images

    assigns = assign(assigns, show?: show?, rows: rows)

    ~H"""
    <div :if={@show?} class="post-content" style="margin-top: 1.5rem">
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
        <tbody>
          <tr :for={image <- @rows}>
            <td><code class="url">{truncate(Map.get(image, :original_url), 80)}</code></td>
            <td>
              <%= if uploaded = Map.get(image, :uploaded_url) do %>
                <code class="url">{truncate(uploaded, 80)}</code>
              <% else %>
                <span class="badge badge-pending-images">pending</span>
              <% end %>
            </td>
            <td>
              <%= if imeta = imeta_summary(image) do %>
                <code>{imeta}</code>
              <% else %>
                —
              <% end %>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp assign_post(socket, post) do
    socket
    |> assign(:post, post)
    |> assign(:editable?, post.status in [Post.status_processed(), Post.status_published()])
    |> assign(:editor, editor_form(post))
    |> assign(:event_html, event_preview_html(post))
    |> assign(:page_title, post.title || "Post")
  end

  defp editor_form(post) do
    %{
      "title" => post.title || "",
      "summary" => post.summary || "",
      "hashtags" => Enum.join(published_hashtags(post), ", "),
      "language" => post.language || "de",
      "content" => post.content || ""
    }
  end

  defp run_action(socket, _name, fun, notice \\ nil) do
    {:noreply,
     socket
     |> assign(:busy, true)
     |> assign(:action_notice, notice)
     |> start_async(:action, fun)}
  end

  defp fetch_post(id) do
    with {:ok, post_id} <- parse_id(id),
         %Post{} = post <- Posts.get_post(post_id, preload: [:source, :images]) do
      {:ok, Processor.finish_if_images_ready(post)}
    else
      _ -> :error
    end
  end

  defp parse_id(id) when is_integer(id), do: {:ok, id}

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> {:ok, int}
      _ -> :error
    end
  end

  defp parse_id(_), do: :error

  defp back_path(post, return_to) do
    cond do
      internal_path?(return_to) -> return_to
      is_integer(post.source_id) -> "/sources/#{post.source_id}?tab=articles"
      true -> "/posts"
    end
  end

  defp internal_path?("//" <> _), do: false
  defp internal_path?("/" <> _), do: true
  defp internal_path?(_), do: false

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: false

  defp uploaded_url(url) do
    if Blossom.already_hosted?(url), do: url
  end

  defp imeta_summary(image) when is_map(image) do
    [
      Map.get(image, :mime_type),
      Map.get(image, :dim),
      Map.get(image, :file_size) && "#{image.file_size} B"
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" · ")
    |> case do
      "" -> nil
      text -> text
    end
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
        "Published as <code>t</code> tags. Omitted from the event: #{Enum.join(omitted, ", ")}."
    end
  end

  defp hashtag_preview_text(post) do
    case published_hashtags(post) do
      [] -> "none"
      tags -> Enum.map_join(tags, ", ", &"##{&1}")
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
            not Source.automated?(source) -> "Waiting for manual publish."
            hold <= 0 -> "Ready to auto-publish."
            rem(hold, 60) == 0 -> "Auto-publishes #{div(hold, 60)}h after staging."
            true -> "Auto-publishes #{hold} minutes after staging."
          end

        "<p><strong>Staged:</strong> #{staged} — #{detail}</p>"
    end
  end

  defp event_tab_intro(post) do
    cond do
      Signer.encrypted_draft?(post.source) ->
        "Inner article <code>EVENT</code> as it will be NIP-44-encrypted into a kind 31234 wrap when published. Long drafts are split so each published <code>[\"EVENT\", wrap]</code> stays under 65535 bytes."

      Signer.plain_draft?(post.source) ->
        "Kind 30024 <code>EVENT</code> signed by the app key when published. Long drafts are split so each published event stays under 65535 bytes."

      true ->
        "Kind 30023 <code>EVENT</code> as it will be signed and published. Long articles are split so each published event stays under 65535 bytes."
    end
  end

  defp event_preview_html(post) do
    preview = Publisher.preview_event(post)
    relays = Enum.map_join(preview.relays, "\n", & &1)
    parts = preview.parts
    total = length(parts)

    note =
      cond do
        preview.draft and total > 1 ->
          "<p class=\"help-text\">This article will be published as #{total} NIP-37 drafts so each published wrap stays within 65535 bytes.</p>"

        preview.draft ->
          "<p class=\"help-text\">This inner article is NIP-44-encrypted into a kind 31234 wrap when published.</p>"

        preview.plain_draft ->
          "<p class=\"help-text\">Published as kind 30024, signed by the app key.</p>"

        true ->
          ""
      end

    part_blocks =
      parts
      |> Enum.with_index(1)
      |> Enum.map_join("", fn {event, index} ->
        heading = if total > 1, do: "<p><strong>Part #{index}/#{total}</strong></p>\n", else: "<p><strong>Message</strong></p>\n"
        json = Jason.encode!(["EVENT", event], pretty: true)
        heading <> ~s(<pre class="compose-preview">#{escape_text(json)}</pre>\n)
      end)

    relay_text = if relays == "", do: "(none configured)", else: relays

    """
    <p><strong>Relays</strong></p>
    <pre class="compose-preview">#{escape_text(relay_text)}</pre>
    #{note}
    #{part_blocks}
    """
  end

  defp escape_text(nil), do: ""

  defp escape_text(str) when is_binary(str) do
    str
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp normalize_one_publish(result) when is_map(result) do
    Map.merge(%{published: 1, failed: 0, errors: []}, result)
  end
end
