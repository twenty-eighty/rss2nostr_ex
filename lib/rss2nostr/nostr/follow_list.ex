defmodule Rss2Nostr.Nostr.FollowList do
  @doc """
  Caches a Nostr kind-3 follow list for one configured pubkey.

  The list is refreshed on startup and then once per hour. Set
  `NOSTR_AUTHORS_FOLLOW_LIST_PUBKEY` to the npub or hex pubkey of the account whose
  contact list should be used.

  Article and video sources keep a stored author `pubkey` in sync whenever an nsec
  or bunker is saved, so follow-list membership checks work without decrypting the
  nsec on every page load.

  Relay fetches run outside the GenServer so `:status` and `:member?` stay fast.
  """

  use GenServer
  require Logger

  alias Rss2Nostr.Nostr.{FollowList.Fetcher, Keys, Signer}
  alias Rss2Nostr.Sources.Source

  @refresh_interval :timer.hours(1)

  defmodule State do
    @moduledoc false
    defstruct pubkey: nil,
              members: MapSet.new(),
              fetched_at: nil,
              error: nil,
              refreshing: false,
              waiters: []
  end

  @type status :: %{
          configured: boolean(),
          pubkey: String.t() | nil,
          count: non_neg_integer(),
          fetched_at: DateTime.t() | nil,
          error: String.t() | nil,
          refreshing: boolean()
        }

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Whether a follow-list pubkey is configured.
  """
  @spec configured?() :: boolean()
  def configured? do
    GenServer.call(__MODULE__, :configured?)
  end

  @doc """
  Returns whether `pubkey` is on the cached follow list.

  When no list is configured, always returns `false`.
  """
  @spec member?(String.t() | nil) :: boolean()
  def member?(pubkey) when is_binary(pubkey) do
    GenServer.call(__MODULE__, {:member?, pubkey})
  end

  def member?(_), do: false

  @doc """
  Returns cache metadata for the UI and settings page.
  """
  @spec status() :: status()
  def status do
    GenServer.call(__MODULE__, :status)
  end

  @doc """
  Starts a background refresh from relays.
  """
  @spec refresh() :: :ok
  def refresh do
    GenServer.cast(__MODULE__, :refresh)
  end

  @doc """
  Refreshes and waits until the fetch finishes or `timeout` is reached.
  """
  @spec refresh_sync(timeout()) :: :ok
  def refresh_sync(timeout \\ 30_000) do
    GenServer.call(__MODULE__, :refresh_sync, timeout)
  end

  @doc """
  Returns sorted hex pubkeys on the cached follow list.
  """
  @spec members() :: [String.t()]
  def members do
    GenServer.call(__MODULE__, :members)
  end

  @doc """
  Follow-list membership for a source.

  Returns `nil` when the list is not configured or the source has no author
  pubkey, `:unknown` when signing is configured but the pubkey could not be
  resolved, otherwise a boolean.
  """
  @spec membership_for_source(Source.t() | map()) :: nil | :unknown | boolean()
  def membership_for_source(source) do
    if configured?() do
      case author_pubkey_for_membership(source) do
        pubkey when is_binary(pubkey) -> member?(pubkey)
        _ -> if article_signer_configured?(source), do: :unknown, else: nil
      end
    end
  end

  @doc """
  JSON-friendly membership value for APIs.
  """
  @spec encode_membership(nil | :unknown | boolean()) :: nil | boolean() | String.t()
  def encode_membership(nil), do: nil
  def encode_membership(:unknown), do: "unknown"
  def encode_membership(bool) when is_boolean(bool), do: bool

  @doc """
  Follow-list block for source responses when a list is configured.
  """
  @spec source_membership_map(Source.t() | map()) :: map() | nil
  def source_membership_map(source) do
    if configured?() do
      %{
        configured: true,
        member: encode_membership(membership_for_source(source))
      }
    end
  end

  @impl true
  def init(_opts) do
    state = %State{pubkey: configured_pubkey()}

    if state.pubkey do
      send(self(), :refresh)
    end

    {:ok, state, {:continue, :schedule}}
  end

  @impl true
  def handle_continue(:schedule, state) do
    schedule_refresh()
    {:noreply, state}
  end

  @impl true
  def handle_call(:configured?, _from, state) do
    {:reply, not is_nil(state.pubkey), state}
  end

  def handle_call({:member?, pubkey}, _from, state) do
    hex =
      case Keys.parse_public_key(pubkey) do
        {:ok, parsed} -> parsed
        {:error, _} -> String.downcase(String.trim(pubkey))
      end

    {:reply, MapSet.member?(state.members, hex), state}
  end

  def handle_call(:status, _from, state) do
    {:reply, status_from_state(state), state}
  end

  def handle_call(:members, _from, state) do
    members = state.members |> MapSet.to_list() |> Enum.sort()
    {:reply, members, state}
  end

  def handle_call(:refresh_sync, from, state) do
    {:noreply, start_refresh(state, from)}
  end

  @impl true
  def handle_cast(:refresh, state) do
    {:noreply, start_refresh(state, nil)}
  end

  @impl true
  def handle_info(:refresh, state) do
    {:noreply, start_refresh(state, nil)}
  end

  @impl true
  def handle_info({:refresh_done, pubkey, result}, state) do
    state =
      state
      |> apply_refresh_result(pubkey, result)
      |> reply_waiters()
      |> Map.put(:refreshing, false)
      |> Map.put(:waiters, [])

    schedule_refresh()
    {:noreply, state}
  end

  @spec start_refresh(State.t(), GenServer.from() | nil) :: State.t()
  defp start_refresh(%State{refreshing: true} = state, nil), do: state

  defp start_refresh(%State{refreshing: true} = state, from) when not is_nil(from) do
    %{state | waiters: [from | state.waiters]}
  end

  defp start_refresh(%State{} = state, from) do
    pubkey = configured_pubkey()

    if is_nil(pubkey) do
      maybe_reply(from, :ok)
      %State{}
    else
      waiters = if from, do: [from | state.waiters], else: state.waiters
      parent = self()

      spawn(fn ->
        result =
          try do
            fetch_members(pubkey)
          catch
            kind, reason -> {:error, {kind, reason}}
          end

        send(parent, {:refresh_done, pubkey, result})
      end)

      %{state | pubkey: pubkey, refreshing: true, waiters: waiters, error: nil}
    end
  end

  @spec apply_refresh_result(State.t(), String.t(), term()) :: State.t()
  defp apply_refresh_result(%State{} = state, pubkey, {:ok, members}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %{
      state
      | pubkey: pubkey,
        members: members,
        fetched_at: now,
        error: nil
    }
  end

  defp apply_refresh_result(%State{} = state, pubkey, {:error, reason}) do
    message = Exception.format(:error, reason)
    Logger.warning("Follow list refresh failed for #{pubkey}: #{message}")

    %{state | pubkey: pubkey, error: message}
  end

  @spec reply_waiters(State.t()) :: State.t()
  defp reply_waiters(%State{waiters: waiters} = state) do
    Enum.each(waiters, &GenServer.reply(&1, :ok))
    state
  end

  @spec maybe_reply(GenServer.from() | nil, term()) :: :ok
  defp maybe_reply(nil, _reply), do: :ok
  defp maybe_reply(from, reply), do: GenServer.reply(from, reply)

  @spec schedule_refresh() :: reference()
  defp schedule_refresh do
    Process.send_after(self(), :refresh, @refresh_interval)
  end

  @spec configured_pubkey() :: String.t() | nil
  defp configured_pubkey do
    Application.get_env(:rss2nostr, :nostr, [])
    |> Keyword.get(:authors_follow_list_pubkey)
    |> case do
      pubkey when is_binary(pubkey) and pubkey != "" -> String.downcase(pubkey)
      _ -> nil
    end
  end

  @spec fetch_members(String.t()) :: {:ok, MapSet.t(String.t())} | {:error, term()}
  defp fetch_members(pubkey) do
    case Application.get_env(:rss2nostr, :nostr, []) |> Keyword.get(:follow_list_fetch) do
      fun when is_function(fun, 1) ->
        fun.(pubkey)

      _ ->
        Fetcher.fetch(pubkey)
    end
  end

  @spec status_from_state(State.t()) :: status()
  defp status_from_state(%State{} = state) do
    %{
      configured: not is_nil(state.pubkey),
      pubkey: state.pubkey,
      count: MapSet.size(state.members),
      fetched_at: state.fetched_at,
      error: state.error,
      refreshing: state.refreshing
    }
  end

  @spec article_signer_configured?(Source.t() | map()) :: boolean()
  defp article_signer_configured?(%{publish_as: publish_as} = source)
       when publish_as in ["article", "video"] do
    Signer.signing_nsec_configured?(source) or present_bunker?(source)
  end

  defp article_signer_configured?(_), do: false

  @spec author_pubkey_for_membership(Source.t() | map()) :: String.t() | nil
  defp author_pubkey_for_membership(%Source{} = source), do: Signer.author_pubkey(source)

  defp author_pubkey_for_membership(%{pubkey: pubkey}) when is_binary(pubkey) and pubkey != "",
    do: String.downcase(pubkey)

  defp author_pubkey_for_membership(_), do: nil

  @spec present_bunker?(map()) :: boolean()
  defp present_bunker?(%{bunker_connection: bunker}) when is_binary(bunker),
    do: String.trim(bunker) != ""

  defp present_bunker?(_), do: false
end
