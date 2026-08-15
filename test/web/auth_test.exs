defmodule Rss2Nostr.Web.AuthTest do
  use Rss2Nostr.ConnCase, async: false

  alias Rss2Nostr.Nostr.{Event, Keys}
  alias Rss2Nostr.Web.Auth

  @admin_hex "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"

  setup do
    pubkey = Keys.derive_public_key(admin_private_key())
    assert Keys.to_hex(pubkey) == @admin_hex
    :ok
  end

  test "pubkeys/0 reads the configured admin allowlist" do
    assert @admin_hex in Auth.pubkeys()
    assert Auth.allowed?(@admin_hex)
    assert Auth.configured?()
  end

  test "login succeeds with a valid NIP-07 event" do
    conn = challenge_conn()
    {conn, payload} = Auth.new_challenge(conn)
    signed = sign_login(payload)

    assert {:ok, conn} = Auth.login(conn, signed)
    assert Auth.logged_in?(conn)
    assert Auth.session_pubkey(conn) == @admin_hex
  end

  test "login rejects a pubkey that is not in the allowlist" do
    original = Application.get_env(:rss2nostr, :admin)

    on_exit(fn ->
      Application.put_env(:rss2nostr, :admin, original)
    end)

    Application.put_env(:rss2nostr, :admin, pubkeys: [String.duplicate("ab", 32)])

    conn = challenge_conn()
    {conn, payload} = Auth.new_challenge(conn)
    signed = sign_login(payload)

    assert {:error, _conn, :unauthorized_pubkey} = Auth.login(conn, signed)
  end

  test "login rejects a reused challenge" do
    conn = challenge_conn()
    {conn, payload} = Auth.new_challenge(conn)
    signed = sign_login(payload)

    assert {:ok, conn} = Auth.login(conn, signed)
    assert {:error, _conn, :missing_challenge} = Auth.login(conn, signed)
  end

  test "login rejects a challenge mismatch" do
    conn = challenge_conn()
    {conn, payload} = Auth.new_challenge(conn)
    signed = sign_login(%{payload | "challenge" => String.duplicate("00", 32)})

    assert {:error, _conn, :challenge_mismatch} = Auth.login(conn, signed)
  end

  test "GET /auth/challenge then POST /auth/login sets the session" do
    challenge_conn = call(conn(:get, "/auth/challenge"), auth: false)
    assert challenge_conn.status == 200
    payload = Jason.decode!(challenge_conn.resp_body)
    signed = sign_login(payload)

    login_conn =
      conn(:post, "/auth/login", Jason.encode!(%{event: stringify_event(signed)}))
      |> put_req_header("content-type", "application/json")
      |> Plug.Test.init_test_session(challenge_conn.private.plug_session)
      |> call()

    assert login_conn.status == 200
    assert Jason.decode!(login_conn.resp_body) == %{"ok" => true}
    assert get_session(login_conn, :admin_pubkey) == @admin_hex
  end

  defp challenge_conn do
    conn(:get, "/auth/challenge")
    |> Map.put(:secret_key_base, Auth.secret_key_base())
    |> Plug.Test.init_test_session(%{})
  end

  defp sign_login(payload) do
    unsigned = %{
      pubkey: @admin_hex,
      created_at: System.os_time(:second),
      kind: payload["kind"],
      tags: [
        ["u", payload["url"]],
        ["method", payload["method"]],
        ["challenge", payload["challenge"]]
      ],
      content: payload["content"]
    }

    {:ok, signed} = Event.sign_event(unsigned, admin_private_key())
    signed
  end

  defp stringify_event(event) do
    %{
      "id" => event.id,
      "pubkey" => event.pubkey,
      "created_at" => event.created_at,
      "kind" => event.kind,
      "tags" => event.tags,
      "content" => event.content,
      "sig" => event.sig
    }
  end
end
