defmodule Rss2Nostr.Web.API.SourcesTest do
  use Rss2Nostr.DataCase

  alias Rss2Nostr.Web.API.Sources, as: API
  alias Rss2Nostr.Sources

  def unique_url do
    "https://example.com/feed-#{System.unique_integer([:positive])}.xml"
  end

  def valid_attrs do
    %{
      name: "Test Source",
      url: unique_url(),
      type: "rss",
      language: "en",
      active: true
    }
  end

  describe "list/0" do
    test "returns empty list when no sources" do
      # Clear existing sources first by listing and checking
      sources = API.list()
      assert is_list(sources)
    end

    test "returns all sources as maps" do
      {:ok, source} = Sources.create_source(valid_attrs())
      sources = API.list()

      assert Enum.any?(sources, fn s ->
               s.id == source.id and
                 s.name == source.name and
                 s.url == source.url
             end)
    end

    test "returns sources with correct structure" do
      {:ok, _} = Sources.create_source(valid_attrs())
      [source | _] = API.list()

      assert Map.has_key?(source, :id)
      assert Map.has_key?(source, :name)
      assert Map.has_key?(source, :url)
      assert Map.has_key?(source, :type)
      assert Map.has_key?(source, :active)
      assert Map.has_key?(source, :language)
      assert Map.has_key?(source, :public)
    end
  end

  describe "create/1" do
    test "creates source with valid params" do
      params = %{
        "name" => "New Source",
        "url" => unique_url(),
        "type" => "atom",
        "language" => "de"
      }

      {:ok, source} = API.create(params)

      assert source.name == "New Source"
      assert source.type == "atom"
      assert source.language == "de"
      assert source.active == true
      assert source.mode == "setup"
      assert source.publish_as == "draft"
      assert source.default_post_kind == 30024
    end

    test "creates an article source when publish_as is article" do
      params = %{
        "name" => "Article Source",
        "url" => unique_url(),
        "type" => "rss",
        "publish_as" => "article",
        "signing_nsec" => "0000000000000000000000000000000000000000000000000000000000000001"
      }

      {:ok, source} = API.create(params)

      assert source.publish_as == "article"
      assert source.default_post_kind == 30023
      assert source.signing_nsec_ciphertext
    end

    test "creates an unencrypted draft source with a pubkey" do
      hex = "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"

      params = %{
        "name" => "Plain Draft Source",
        "url" => unique_url(),
        "publish_as" => "draft_plain",
        "pubkey" => hex
      }

      {:ok, source} = API.create(params)
      assert source.publish_as == "draft_plain"
      assert source.default_post_kind == 30024
      assert source.pubkey == hex
    end

    test "requires a pubkey when creating a draft source" do
      params = %{
        "name" => "Draft Source",
        "url" => unique_url(),
        "publish_as" => "draft"
      }

      assert {:error, changeset} = API.create(params)
      assert changeset.errors[:pubkey]
    end

    test "requires an nsec or bunker when creating an article source" do
      params = %{
        "name" => "Article Source",
        "url" => unique_url(),
        "publish_as" => "article"
      }

      assert {:error, changeset} = API.create(params)
      assert changeset.errors[:signing_nsec]
    end

    test "creates source with author pubkey as drafts" do
      hex = "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"

      params = %{
        "name" => "Author Source",
        "url" => unique_url(),
        "pubkey" => hex,
        "start_guid" => "article-1",
        "start_published_at" => "2024-01-01T12:00:00Z"
      }

      {:ok, source} = API.create(params)

      assert source.pubkey == hex
      assert source.default_post_kind == 30024
      assert source.options["start_guid"] == "article-1"
      assert source.publish_after_date
    end

    test "stores composition settings" do
      params = %{
        "name" => "Compose Source",
        "url" => unique_url(),
        "fetch_source_from" => "content",
        "body_selector" => "div.entry-content",
        "start_at" => "//p[contains(., 'Lecture')]",
        "skip_classes" => "lead, OUTBRAIN"
      }

      {:ok, source} = API.create(params)

      assert source.fetch_source_from == "content"
      assert source.options["body_selector"] == "div.entry-content"
      assert source.options["start_at"] == "//p[contains(., 'Lecture')]"
      assert source.options["skip_classes"] == ["lead", "OUTBRAIN"]
    end

    test "stores conversion rules" do
      params = %{
        "name" => "Rules Source",
        "url" => unique_url(),
        "conversion_rules" =>
          Jason.encode!([
            %{
              "action" => "links_as_paragraphs",
              "xpath" => "//p[contains(., 'WATCH ON:')]"
            }
          ])
      }

      {:ok, source} = API.create(params)

      assert [%{action: "links_as_paragraphs", xpath: xpath}] = source.options["conversion_rules"]
      assert xpath == "//p[contains(., 'WATCH ON:')]"
    end

    test "uses default values when not provided" do
      params = %{
        "name" => "Default Source",
        "url" => unique_url()
      }

      {:ok, source} = API.create(params)

      assert source.type == "atom"
      assert source.language == "de"
      assert source.public == false
    end

    test "stores the Corbett body selector from the feed URL" do
      params = %{
        "name" => "Corbett Interviews",
        "url" => "https://www.corbettreport.com/feed-#{System.unique_integer([:positive])}.xml"
      }

      {:ok, source} = API.create(params)

      assert source.options["body_selector"] == "div.et_pb_column_0_tb_body"
    end

    test "returns error for invalid params" do
      params = %{"name" => nil, "url" => nil}

      {:error, changeset} = API.create(params)
      refute changeset.valid?
    end
  end

  describe "update/2" do
    test "updates composition settings without dropping start_guid" do
      {:ok, source} =
        Sources.create_source(
          Map.merge(valid_attrs(), %{
            options: %{"start_guid" => "keep-me"},
            fetch_source_from: "fetch_from_url"
          })
        )

      {:ok, updated} =
        API.update(source, %{
          "fetch_source_from" => "content",
          "body_selector" => "article",
          "skip_classes" => "shariff"
        })

      assert updated.fetch_source_from == "content"
      assert updated.options["start_guid"] == "keep-me"
      assert updated.options["body_selector"] == "article"
      assert updated.options["skip_classes"] == ["shariff"]
    end

    test "fills a missing Corbett body selector when feed settings are saved" do
      url = "https://www.corbettreport.com/feed-#{System.unique_integer([:positive])}.xml"

      {:ok, source} =
        Sources.create_source(Map.merge(valid_attrs(), %{url: url, options: %{}}))

      {:ok, updated} = API.update(source, %{"name" => source.name, "url" => url})

      assert updated.options["body_selector"] == "div.et_pb_column_0_tb_body"
    end

    test "keeps stored conversion rules when compose is saved without them" do
      {:ok, source} =
        Sources.create_source(
          Map.merge(valid_attrs(), %{
            options: %{
              "conversion_rules" => [
                %{
                  "action" => "links_as_paragraphs",
                  "xpath" => "//p[contains(., 'WATCH ON:')]"
                }
              ]
            }
          })
        )

      {:ok, updated} =
        API.update(source, %{
          "body_selector" => "div.et_pb_column_0_tb_body",
          "start_at" => "",
          "skip_classes" => ""
        })

      [rule] = updated.options["conversion_rules"]
      assert (rule[:xpath] || rule["xpath"]) == "//p[contains(., 'WATCH ON:')]"
    end

    test "stores fixed hashtags from publishing settings" do
      {:ok, source} = Sources.create_source(valid_attrs())

      {:ok, updated} =
        API.update(source, %{"fixed_hashtags" => "#PatrikBaab, bitcoin, patrikbaab"})

      assert updated.fixed_hashtags == ["patrikbaab", "bitcoin"]
    end
  end

  describe "compose_preview/1" do
    test "returns an error without a feed URL" do
      assert {:error, "Feed URL is required"} = API.compose_preview(%{})
    end
  end

  describe "toggle/1" do
    test "disables active source" do
      {:ok, source} = Sources.create_source(%{valid_attrs() | active: true})

      {:ok, toggled} = API.toggle(to_string(source.id))
      assert toggled.active == false
    end

    test "enables inactive source" do
      {:ok, source} = Sources.create_source(%{valid_attrs() | active: false})

      {:ok, toggled} = API.toggle(to_string(source.id))
      assert toggled.active == true
    end

    test "returns error for non-existent source" do
      assert {:error, :not_found} = API.toggle("999999")
    end

    test "returns error for invalid id" do
      assert {:error, :invalid_id} = API.toggle("invalid")
      assert {:error, :invalid_id} = API.toggle("-1")
      assert {:error, :invalid_id} = API.toggle("0")
    end
  end

  describe "duplicate/1" do
    test "duplicates an existing source" do
      {:ok, source} = Sources.create_source(valid_attrs())

      {:ok, copy} = API.duplicate(to_string(source.id))

      assert copy.id != source.id
      assert copy.name == "#{source.name} (copy)"
      assert copy.url != source.url
    end

    test "returns error for a missing source" do
      assert {:error, :not_found} = API.duplicate("999999")
    end
  end

  describe "delete/1" do
    test "deletes existing source" do
      {:ok, source} = Sources.create_source(valid_attrs())

      {:ok, _} = API.delete(to_string(source.id))
      assert Sources.get_source(source.id) == nil
    end

    test "returns error for non-existent source" do
      assert {:error, :not_found} = API.delete("999999")
    end

    test "returns error for invalid id" do
      assert {:error, :invalid_id} = API.delete("invalid")
      assert {:error, :invalid_id} = API.delete("-1")
    end
  end
end
