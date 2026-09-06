defmodule Rss2Nostr.Nostr.RelayTest do
  use ExUnit.Case, async: false

  alias Rss2Nostr.Nostr.Relay

  @event %{
    id: String.duplicate("a", 64),
    pubkey: String.duplicate("b", 64),
    created_at: 0,
    kind: 1,
    tags: [],
    content: "test",
    sig: String.duplicate("c", 128)
  }

  test "format_error/1 explains connection and relay rejections" do
    assert Relay.format_error(%WebSockex.ConnError{original: :nxdomain}) ==
             "could not resolve host"

    assert Relay.format_error("invalid: event too large: 87959") ==
             "invalid: event too large: 87959"

    assert Relay.format_error(:timeout) == "timed out"

    assert Relay.format_error({:timeout, {:gen_server, :call, [:pid, {:publish, %{}}]}}) ==
             "timed out"
  end

  test "rate_limited?/1 detects Damus-style rejections" do
    assert Relay.rate_limited?("rate-limited: you are noting too much")
    assert Relay.rate_limited?("slow down")
    refute Relay.rate_limited?("connection refused")
  end

  test "publish_to_relays returns an error instead of crashing on nxdomain" do
    url = "wss://no-such-relay.invalid"

    assert [{^url, {:error, reason}}] = Relay.publish_to_relays([url], @event, 3_000)
    assert reason == :nxdomain or match?(%WebSockex.ConnError{}, reason)
  after
    Relay.disconnect("wss://no-such-relay.invalid")
  end

  test "query/3 returns an error instead of crashing on nxdomain" do
    url = "wss://no-such-query-relay.invalid"

    assert {:error, reason} = Relay.query(url, %{"kinds" => [1], "limit" => 1}, 3_000)
    assert reason == :nxdomain or match?(%WebSockex.ConnError{}, reason)
  after
    Relay.disconnect("wss://no-such-query-relay.invalid")
  end

  test "query/3 returns {:error, :timeout} instead of exiting when the relay never replies" do
    url = "wss://hang-query-relay.test"
    name = {:via, Registry, {Rss2Nostr.RelayRegistry, url}}

    {:ok, _pid} = Rss2Nostr.Nostr.RelayTest.HangRelay.start_link(name: name)

    assert {:error, :timeout} = Relay.query(url, %{"kinds" => [0], "limit" => 1}, 200)
  after
    case Registry.lookup(Rss2Nostr.RelayRegistry, "wss://hang-query-relay.test") do
      [{pid, _}] -> GenServer.stop(pid, :normal, 1_000)
      [] -> :ok
    end
  end
end

defmodule Rss2Nostr.Nostr.RelayTest.HangRelay do
  @moduledoc false
  use GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, nil, opts)
  def init(_), do: {:ok, %{}}
  def handle_call(_msg, _from, state), do: {:noreply, state}
end
