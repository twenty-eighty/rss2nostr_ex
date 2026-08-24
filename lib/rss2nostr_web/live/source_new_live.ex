defmodule Rss2NostrWeb.SourceNewLive do
  @moduledoc false

  use Rss2NostrWeb, :live_view

  alias Rss2Nostr.Web.API.Sources, as: SourcesAPI

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Add Source")
     |> assign(:active_nav, "sources")
     |> assign(:wide, true)
     |> assign(:errors, %{})
     |> assign(:busy, false)
     |> assign(:discover_status, nil)
     |> assign(:discover_error, nil)
     |> assign(:feeds, [])
     |> assign(:items, [])
     |> assign(:details?, false)
     |> assign(:form, default_form())}
  end

  @impl true
  def handle_event("form_changed", params, socket) do
    form = merge_form(socket.assigns.form, params)

    form =
      if params["_target"] == ["start_guid"] do
        guid = form["start_guid"]

        published_at =
          case Enum.find(socket.assigns.items, &(item_guid(&1) == guid)) do
            %{published_at: published} -> published
            %{"published_at" => published} -> published
            _ -> ""
          end

        Map.put(form, "start_published_at", published_at || "")
      else
        form
      end

    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("discover", _params, socket) do
    discover(socket)
  end

  def handle_event("save", params, socket) do
    form =
      socket.assigns.form
      |> merge_form(params)
      |> maybe_url_from_website()

    cond do
      complete?(form, socket.assigns.items) ->
        case SourcesAPI.create(form) do
          {:ok, source} ->
            {:noreply, push_navigate(socket, to: "/sources/#{source.id}")}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply,
             socket
             |> assign(:form, form)
             |> assign(:details?, true)
             |> assign(:errors, changeset_errors(changeset))
             |> put_flash(:error, format_update_error(changeset))}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, format_update_error(reason))}
        end

      not socket.assigns.details? ->
        discover(assign(socket, :form, form))

      true ->
        {:noreply,
         socket
         |> assign(:form, form)
         |> put_flash(:error, "Fill in the feed details before adding the source.")}
    end
  end

  def handle_event("pick_feed", %{"url" => url} = params, socket) do
    feed = Enum.find(socket.assigns.feeds, &(feed_url(&1) == url))
    type = feed_type(feed) || params["type"] || socket.assigns.form["type"]

    form =
      socket.assigns.form
      |> Map.put("url", url)
      |> Map.put("type", type || "atom")

    {:noreply,
     socket
     |> assign(:form, form)
     |> assign(:discover_status, "Loading articles…")
     |> assign(:discover_error, nil)
     |> start_async(:preview, fn -> SourcesAPI.preview(%{"url" => url}) end)}
  end

  @impl true
  def handle_async(:discover, {:ok, {:ok, result}}, socket) do
    feeds = result[:feeds] || result["feeds"] || []
    items = result[:items] || result["items"] || []
    page_title = result[:page_title] || result["page_title"]
    language = language_from(result)
    direct? = result[:direct_feed] || result["direct_feed"]
    selected = List.first(feeds)

    form =
      socket.assigns.form
      |> maybe_put_name(page_title)
      |> maybe_put_language(language)
      |> maybe_put_feed(selected)
      |> maybe_put_start(items)

    socket =
      socket
      |> assign(:busy, false)
      |> assign(:details?, feeds != [])
      |> assign(:feeds, feeds)
      |> assign(:items, items)
      |> assign(:form, form)
      |> assign(:discover_error, if(feeds == [], do: "No RSS or Atom feeds found on this page."))
      |> assign(:discover_status, if(direct?, do: "Using this feed URL.", else: nil))

    socket =
      if feeds != [] and items == [] and selected do
        url = feed_url(selected)

        socket
        |> assign(:discover_status, "Loading articles…")
        |> start_async(:preview, fn -> SourcesAPI.preview(%{"url" => url}) end)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_async(:discover, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:busy, false)
     |> assign(:discover_status, nil)
     |> assign(:discover_error, to_string(reason))}
  end

  def handle_async(:discover, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:busy, false)
     |> assign(:discover_status, nil)
     |> assign(:discover_error, Exception.format_exit(reason))}
  end

  def handle_async(:preview, {:ok, {:ok, result}}, socket) do
    items = result[:items] || result["items"] || []
    language = language_from(result)
    type = feed_type(result) || socket.assigns.form["type"]

    form =
      socket.assigns.form
      |> maybe_put_language(language)
      |> Map.put("type", type)
      |> maybe_put_start(items)

    {:noreply,
     socket
     |> assign(:items, items)
     |> assign(:form, form)
     |> assign(:discover_status, nil)
     |> assign(:discover_error, nil)}
  end

  def handle_async(:preview, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:items, [])
     |> assign(:discover_status, nil)
     |> assign(:discover_error, to_string(reason))}
  end

  def handle_async(:preview, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:items, [])
     |> assign(:discover_status, nil)
     |> assign(:discover_error, Exception.format_exit(reason))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h1>Add Source</h1>

    <form id="add-source-form" phx-change="form_changed" phx-submit="save" class="form form-wide form-compose">
      <div class="form-group">
        <label for="website">Website or feed URL</label>
        <div class="input-row">
          <input
            type="text"
            id="website"
            name="website"
            inputmode="url"
            autocomplete="url"
            placeholder="https://example.com or https://example.com/feed.xml"
            value={@form["website"]}
          />
          <button type="button" class="btn btn-secondary" id="discover-button" phx-click="discover" disabled={@busy}>
            Find feeds
          </button>
        </div>
        <p class="help-text">Paste a website to discover its feeds, or paste an RSS/Atom URL directly.</p>
        <p id="discover-status" class="help-text">{@discover_status}</p>
        <p :if={@discover_error} id="discover-error" class="error">{@discover_error}</p>
      </div>

      <div id="source-details" hidden={not @details?}>
        <div class="form-group" id="feeds-group">
          <label>Feeds</label>
          <div id="feeds-list" class="choice-list">
            <label :for={feed <- @feeds} class="choice">
              <input
                type="radio"
                name="feed_choice"
                value={feed_url(feed)}
                checked={feed_url(feed) == @form["url"]}
                phx-click="pick_feed"
                phx-value-url={feed_url(feed)}
                phx-value-type={feed_type(feed)}
              />
              <span>
                <strong>{feed_title(feed)}</strong>
                <code class="url">{feed_url(feed)}</code>
              </span>
            </label>
          </div>
          <.field_error field={:url} errors={@errors} />
        </div>

        <input type="hidden" id="url" name="url" value={@form["url"]} />
        <input type="hidden" id="type" name="type" value={@form["type"]} />
        <input
          type="hidden"
          id="start_published_at"
          name="start_published_at"
          value={@form["start_published_at"]}
        />

        <div class="form-group">
          <label for="name">Name</label>
          <input type="text" id="name" name="name" required placeholder="e.g., Heise News" value={@form["name"]} />
          <.field_error field={:name} errors={@errors} />
        </div>

        <div class="form-group">
          <label for="start_article">Start import from</label>
          <select id="start_article" name="start_guid">
            <%= if @discover_status == "Loading articles…" do %>
              <option value="">Loading articles…</option>
            <% else %>
              <option :if={@items == []} value="">No articles found in this feed</option>
              <option
                :for={item <- @items}
                value={item_guid(item)}
                selected={item_guid(item) == @form["start_guid"]}
              >
                {item_label(item)}
              </option>
            <% end %>
          </select>
          <p class="help-text">
            Articles older than this one are skipped. Newer items in later fetches are still imported.
          </p>
        </div>

        <div class="form-group">
          <label for="language">Language</label>
          <select id="language" name="language">
            <option
              :for={{code, label} <- language_options(@form["language"])}
              value={code}
              selected={code == @form["language"]}
            >
              {label}
            </option>
          </select>
        </div>

        <.publish_as_fields form={@form} errors={@errors} />

        <div class="form-group">
          <label for="fixed_hashtags">Fixed hashtags</label>
          <input
            type="text"
            id="fixed_hashtags"
            name="fixed_hashtags"
            value={@form["fixed_hashtags"]}
            placeholder="comma-separated"
          />
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
            value={@form["excluded_hashtags"]}
            placeholder="ROOT, Haupteintrag"
          />
          <p class="help-text">
            RSS categories on every item (for example <code>ROOT</code>, <code>Haupteintrag</code>)
            are dropped from published <code>t</code> tags.
          </p>
        </div>
      </div>

      <div class="form-actions">
        <button
          type="submit"
          class="btn btn-primary"
          id="submit-source"
          disabled={not complete?(@form, @items) or @busy}
        >
          Add Source
        </button>
        <a href="/sources" class="btn btn-secondary">Cancel</a>
      </div>
    </form>
    """
  end

  defp publish_as_fields(assigns) do
    publish_as = assigns.form["publish_as"] || "draft"

    assigns =
      assigns
      |> assign(:publish_as, publish_as)
      |> assign(:draft?, publish_as in ["draft", "draft_plain"])
      |> assign(:article?, publish_as in ["article", "video"])
      |> assign(:video?, publish_as == "video")

    ~H"""
    <fieldset class="compose-fieldset">
      <legend>Publish as</legend>
      <div class="choice-list">
        <label class="choice">
          <input type="radio" name="publish_as" value="draft" checked={@publish_as == "draft"} />
          <span>
            <strong>Draft (encrypted, NIP-37)</strong>
            <span class="help-text">Signed by the app key and NIP-44-encrypted into a kind 31234 wrap. The author’s pubkey is a <code>p</code> tag.</span>
          </span>
        </label>
        <label class="choice">
          <input type="radio" name="publish_as" value="draft_plain" checked={@publish_as == "draft_plain"} />
          <span>
            <strong>Draft (unencrypted)</strong>
            <span class="help-text">A kind 30024 event signed by the app key. The author’s pubkey is a <code>p</code> tag.</span>
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
            <input type="radio" name="mirror_media" value="blossom" checked={@form["mirror_media"] != "original"} />
            <span>
              <strong>Mirror to Blossom</strong>
              <span class="help-text">Upload the MP4 to <code>NOSTR_UPLOAD_ENDPOINT</code> and put that URL on the event.</span>
            </span>
          </label>
          <label class="choice">
            <input type="radio" name="mirror_media" value="original" checked={@form["mirror_media"] == "original"} />
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
          value={@form["pubkey"]}
          autocomplete="off"
        />
        <.field_error field={:pubkey} errors={@errors} />
        <p class="help-text">Required for drafts. Added as a <code>p</code> tag so the intended author is known.</p>
      </div>
    </div>

    <div id="article-signer-fields" hidden={not @article?}>
      <div class="form-group">
        <label for="signing_nsec">Author private key (nsec)</label>
        <input type="password" id="signing_nsec" name="signing_nsec" autocomplete="new-password" placeholder="nsec1…" />
        <.field_error field={:signing_nsec} errors={@errors} />
        <p class="help-text">Required for articles and videos unless a bunker URL is set. Stored encrypted.</p>
      </div>
      <div class="form-group">
        <label for="bunker_connection">Bunker URL</label>
        <input
          type="text"
          id="bunker_connection"
          name="bunker_connection"
          placeholder="bunker://…?relay=wss://…"
          value={@form["bunker_connection"]}
          autocomplete="off"
        />
      </div>
    </div>
    """
  end

  defp discover(socket) do
    url = String.trim(socket.assigns.form["website"] || "")

    if url == "" do
      {:noreply, assign(socket, :discover_error, "Enter a website or feed URL.")}
    else
      {:noreply,
       socket
       |> assign(:busy, true)
       |> assign(:discover_error, nil)
       |> assign(:discover_status, "Looking for feeds…")
       |> start_async(:discover, fn -> SourcesAPI.discover(%{"url" => url}) end)}
    end
  end

  defp default_form do
    %{
      "website" => "",
      "url" => "",
      "type" => "atom",
      "name" => "",
      "language" => "de",
      "start_guid" => "",
      "start_published_at" => "",
      "publish_as" => "draft",
      "mirror_media" => "blossom",
      "pubkey" => "",
      "signing_nsec" => "",
      "bunker_connection" => "",
      "fixed_hashtags" => "",
      "excluded_hashtags" => ""
    }
  end

  defp merge_form(form, params) do
    Enum.reduce(form, form, fn {key, _}, acc ->
      case Map.fetch(params, key) do
        {:ok, value} -> Map.put(acc, key, value)
        :error -> acc
      end
    end)
  end

  defp maybe_url_from_website(form) do
    if present?(form["url"]) or not present?(form["website"]) do
      form
    else
      Map.put(form, "url", String.trim(form["website"]))
    end
  end

  defp complete?(form, items) do
    present?(form["url"]) and present?(form["name"]) and present?(form["language"]) and
      start_ok?(form, items) and identity_ok?(form)
  end

  defp start_ok?(form, items) do
    cond do
      items == [] and present?(form["url"]) -> true
      present?(form["start_guid"]) -> true
      true -> false
    end
  end

  defp identity_ok?(form) do
    case form["publish_as"] do
      value when value in ["article", "video"] ->
        present?(form["signing_nsec"]) or present?(form["bunker_connection"])

      _ ->
        present?(form["pubkey"])
    end
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: false

  defp maybe_put_name(form, title) do
    if present?(form["name"]) or not present?(title), do: form, else: Map.put(form, "name", title)
  end

  defp maybe_put_language(form, language) do
    if present?(language), do: Map.put(form, "language", String.downcase(language)), else: form
  end

  defp maybe_put_feed(form, nil), do: form

  defp maybe_put_feed(form, feed) do
    form
    |> Map.put("url", feed_url(feed))
    |> Map.put("type", feed_type(feed) || form["type"])
  end

  defp maybe_put_start(form, []), do: Map.merge(form, %{"start_guid" => "", "start_published_at" => ""})

  defp maybe_put_start(form, items) do
    item = List.last(items)

    form
    |> Map.put("start_guid", item_guid(item))
    |> Map.put("start_published_at", item_published(item) || "")
  end

  defp language_from(result) do
    result[:language] || result["language"] ||
      case List.first(result[:feeds] || result["feeds"] || []) do
        %{language: language} -> language
        %{"language" => language} -> language
        _ -> nil
      end
  end

  defp feed_url(%{url: url}), do: url
  defp feed_url(%{"url" => url}), do: url
  defp feed_url(_), do: ""

  defp feed_title(%{title: title}) when is_binary(title) and title != "", do: title
  defp feed_title(%{"title" => title}) when is_binary(title) and title != "", do: title
  defp feed_title(_), do: "Untitled feed"

  defp feed_type(%{type: type}), do: type
  defp feed_type(%{"type" => type}), do: type
  defp feed_type(%{feeds: [feed | _]}), do: feed_type(feed)
  defp feed_type(%{"feeds" => [feed | _]}), do: feed_type(feed)
  defp feed_type(_), do: nil

  defp item_guid(%{guid: guid}), do: guid || ""
  defp item_guid(%{"guid" => guid}), do: guid || ""
  defp item_guid(_), do: ""

  defp item_published(%{published_at: published}), do: published
  defp item_published(%{"published_at" => published}), do: published
  defp item_published(_), do: nil

  defp item_label(item) do
    date =
      case item_published(item) do
        published when is_binary(published) and published != "" -> String.slice(published, 0, 10) <> " — "
        _ -> ""
      end

    title =
      case item do
        %{title: title} when is_binary(title) and title != "" -> title
        %{"title" => title} when is_binary(title) and title != "" -> title
        _ ->
          case item_guid(item) do
            "" -> "Untitled"
            guid -> guid
          end
      end

    date <> title
  end
end
