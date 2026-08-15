defmodule Rss2Nostr.SourcesTest do
  use Rss2Nostr.DataCase

  alias Rss2Nostr.Sources
  alias Rss2Nostr.Posts
  alias Rss2Nostr.Posts.Post

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

  describe "list_sources/0" do
    test "returns all sources" do
      {:ok, source} = Sources.create_source(valid_attrs())
      sources = Sources.list_sources()

      assert sources != []
      assert Enum.any?(sources, fn s -> s.id == source.id end)
    end
  end

  describe "list_active_sources/0" do
    test "returns only active sources" do
      {:ok, active} = Sources.create_source(%{valid_attrs() | active: true})
      {:ok, inactive} = Sources.create_source(%{valid_attrs() | name: "Inactive", active: false})

      sources = Sources.list_active_sources()

      assert Enum.any?(sources, fn s -> s.id == active.id end)
      refute Enum.any?(sources, fn s -> s.id == inactive.id end)
    end
  end

  describe "get_source/1" do
    test "returns the source with given id" do
      {:ok, source} = Sources.create_source(valid_attrs())
      found = Sources.get_source(source.id)

      assert found.id == source.id
      assert found.name == source.name
    end

    test "returns nil for non-existent id" do
      assert Sources.get_source(-1) == nil
    end
  end

  describe "get_source!/1" do
    test "returns the source with given id" do
      {:ok, source} = Sources.create_source(valid_attrs())
      found = Sources.get_source!(source.id)

      assert found.id == source.id
    end

    test "raises for non-existent id" do
      assert_raise Ecto.NoResultsError, fn ->
        Sources.get_source!(-1)
      end
    end
  end

  describe "create_source/1" do
    test "creates source with valid attrs" do
      attrs = valid_attrs()
      {:ok, source} = Sources.create_source(attrs)

      assert source.name == "Test Source"
      assert source.url == attrs.url
      assert source.type == "rss"
      assert source.active == true
      assert source.mode == "setup"
      assert source.publish_as == "draft"
    end

    test "requires a pubkey when publish_as is draft" do
      {:error, changeset} =
        Sources.create_source(Map.put(valid_attrs(), :publish_as, "draft"))

      refute changeset.valid?
      assert changeset.errors[:pubkey]
    end

    test "requires an nsec or bunker when publish_as is article" do
      {:error, changeset} =
        Sources.create_source(Map.put(valid_attrs(), :publish_as, "article"))

      refute changeset.valid?
      assert changeset.errors[:signing_nsec]
    end

    test "requires a signer before switching to automated article mode" do
      {:ok, source} = Sources.create_source(valid_attrs())

      {:error, changeset} =
        Sources.update_source(source, %{mode: "automated", publish_as: "article"})

      refute changeset.valid?
      assert changeset.errors[:mode]
    end

    test "defaults public to false" do
      {:ok, source} = Sources.create_source(valid_attrs())
      assert source.public == false
    end

    test "creates a public source" do
      {:ok, source} = Sources.create_source(Map.put(valid_attrs(), :public, true))
      assert source.public == true
    end

    test "returns error changeset with invalid attrs" do
      {:error, changeset} = Sources.create_source(%{name: nil, url: nil})

      refute changeset.valid?
    end

    test "stores an author npub as hex and uses draft kind" do
      hex = "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
      {:ok, npub} = Rss2Nostr.Nostr.NIP19.encode_npub(hex)

      {:ok, source} =
        Sources.create_source(Map.merge(valid_attrs(), %{pubkey: npub}))

      assert source.pubkey == hex
      assert source.default_post_kind == 30024
    end

    test "rejects an invalid fetch_source_from value" do
      {:error, changeset} =
        Sources.create_source(Map.merge(valid_attrs(), %{fetch_source_from: "readability"}))

      refute changeset.valid?
      assert changeset.errors[:fetch_source_from]
    end

    test "rejects an invalid author pubkey" do
      {:error, changeset} =
        Sources.create_source(Map.merge(valid_attrs(), %{pubkey: "not-a-key"}))

      refute changeset.valid?
      assert changeset.errors[:pubkey]
    end
  end

  describe "update_source/2" do
    test "updates source with valid attrs" do
      {:ok, source} = Sources.create_source(valid_attrs())
      {:ok, updated} = Sources.update_source(source, %{name: "Updated Name"})

      assert updated.name == "Updated Name"
      assert updated.id == source.id
    end
  end

  describe "duplicate_source/2" do
    test "copies settings into a new setup source with a unique URL" do
      hex = "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"

      {:ok, source} =
        Sources.create_source(
          Map.merge(valid_attrs(), %{
            name: "Corbett Podcast",
            publish_as: "draft",
            pubkey: hex,
            public: true,
            fetch_source_from: "content",
            options: %{
              "body_selector" => "div.et_pb_column_0_tb_body",
              "skip_classes" => ["OUTBRAIN"],
              "start_guid" => "old-episode"
            }
          })
        )

      {:ok, copy} = Sources.duplicate_source(source)

      assert copy.id != source.id
      assert copy.name == "Corbett Podcast (copy)"
      assert copy.url != source.url
      assert String.starts_with?(copy.url, source.url)
      assert copy.mode == "setup"
      assert copy.publish_as == "draft"
      assert copy.pubkey == hex
      assert copy.public == true
      assert copy.fetch_source_from == "content"
      assert copy.options["body_selector"] == "div.et_pb_column_0_tb_body"
      assert copy.options["skip_classes"] == ["OUTBRAIN"]
      refute Map.has_key?(copy.options, "start_guid")
      assert is_nil(copy.publish_after_date)
    end

    test "accepts a new feed URL and name" do
      {:ok, source} = Sources.create_source(valid_attrs())
      url = unique_url()

      {:ok, copy} =
        Sources.duplicate_source(source, %{name: "Interviews", url: url})

      assert copy.name == "Interviews"
      assert copy.url == url
    end

    test "copies an article signer" do
      hex = "0000000000000000000000000000000000000000000000000000000000000001"

      {:ok, source} =
        Sources.create_source(
          Map.merge(valid_attrs(), %{
            publish_as: "article",
            signing_nsec: hex
          })
        )

      {:ok, copy} = Sources.duplicate_source(source)

      assert copy.publish_as == "article"
      assert copy.signing_nsec_ciphertext == source.signing_nsec_ciphertext
    end
  end

  describe "delete_source/1" do
    test "deletes the source" do
      {:ok, source} = Sources.create_source(valid_attrs())
      {:ok, _deleted} = Sources.delete_source(source)

      assert Sources.get_source(source.id) == nil
    end

    test "deletes the source's articles" do
      {:ok, source} = Sources.create_source(valid_attrs())
      url = "https://example.com/article/#{System.unique_integer([:positive])}"

      {:ok, post} =
        Posts.create_post(%{
          title: "Cascaded Article",
          source_url: url,
          source_url_hash: Post.generate_url_hash(url),
          source_html: "<p>Content</p>",
          status: Post.status_new(),
          source_id: source.id
        })

      {:ok, _} = Sources.delete_source(source)

      assert Sources.get_source(source.id) == nil
      assert Posts.get_post(post.id) == nil
    end
  end

  describe "enable_source/1" do
    test "enables an inactive source" do
      {:ok, source} = Sources.create_source(%{valid_attrs() | active: false})
      {:ok, enabled} = Sources.enable_source(source)

      assert enabled.active == true
    end

    test "enables source by id" do
      {:ok, source} = Sources.create_source(%{valid_attrs() | active: false})
      {:ok, enabled} = Sources.enable_source(source.id)

      assert enabled.active == true
    end
  end

  describe "disable_source/1" do
    test "disables an active source" do
      {:ok, source} = Sources.create_source(%{valid_attrs() | active: true})
      {:ok, disabled} = Sources.disable_source(source)

      assert disabled.active == false
    end

    test "disables source by id" do
      {:ok, source} = Sources.create_source(%{valid_attrs() | active: true})
      {:ok, disabled} = Sources.disable_source(source.id)

      assert disabled.active == false
    end
  end

  describe "count_sources/0" do
    test "returns total count of sources" do
      initial_count = Sources.count_sources()

      {:ok, _} = Sources.create_source(valid_attrs())
      {:ok, _} = Sources.create_source(%{valid_attrs() | name: "Second"})

      assert Sources.count_sources() == initial_count + 2
    end
  end

  describe "count_active_sources/0" do
    test "returns count of active sources" do
      initial_count = Sources.count_active_sources()

      {:ok, _} = Sources.create_source(%{valid_attrs() | active: true})
      {:ok, _} = Sources.create_source(%{valid_attrs() | name: "Inactive", active: false})

      assert Sources.count_active_sources() == initial_count + 1
    end
  end
end
