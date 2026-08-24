defmodule Rss2Nostr.Web.CodeReloader do
  @moduledoc """
  Recompiles changed Elixir modules on each request in development.

  CSS and page JavaScript live in view modules, so this also refreshes
  those after a normal browser reload. Disabled outside Mix dev.
  """

  use GenServer

  require Logger

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  @spec init(term()) :: {:ok, map()}
  def init(_opts), do: {:ok, %{}}

  @impl GenServer
  @spec handle_call(:reload, GenServer.from(), map()) :: {:reply, :ok | :noop | :error, map()}
  def handle_call(:reload, _from, state) do
    {:reply, do_reload(), state}
  end

  @spec enabled?() :: boolean()
  def enabled? do
    Application.get_env(:rss2nostr, :code_reloader, false)
  end

  @spec reload() :: :ok | :noop | :error
  def reload do
    cond do
      not enabled?() ->
        :noop

      pid = Process.whereis(__MODULE__) ->
        GenServer.call(pid, :reload, :infinity)

      true ->
        do_reload()
    end
  end

  @spec plug(Plug.Conn.t(), term()) :: Plug.Conn.t()
  def plug(conn, _opts) do
    reload()
    conn
  end

  @spec do_reload() :: :ok | :noop | :error
  defp do_reload do
    if Code.ensure_loaded?(Mix.Task) and function_exported?(Mix.Task, :reenable, 1) do
      Mix.Task.reenable("compile.elixir")
      Mix.Task.reenable("compile")
      Mix.Task.run("compile.elixir")
      reload_updated_modules()
      :ok
    else
      :noop
    end
  rescue
    error ->
      Logger.error("[CodeReloader] #{Exception.message(error)}")
      :error
  end

  # Mix compile is a no-op when another process already wrote fresh beams
  # (tests, migrate). Reload those into this VM so new function arities exist.
  @spec reload_updated_modules() :: :ok
  defp reload_updated_modules do
    ebin = Application.app_dir(:rss2nostr, "ebin")

    case :application.get_key(:rss2nostr, :modules) do
      {:ok, modules} -> Enum.each(modules, &reload_if_stale(&1, ebin))
      :undefined -> :ok
    end
  end

  @spec reload_if_stale(module(), String.t()) :: :ok
  defp reload_if_stale(module, ebin) do
    beam = Path.join(ebin, Atom.to_string(module) <> ".beam")

    with true <- File.exists?(beam),
         loaded when loaded != false <- :code.is_loaded(module),
         {:ok, disk_time} <- beam_compile_time(beam),
         memory_time when memory_time != disk_time <- memory_compile_time(module) do
      :code.purge(module)
      :code.load_abs(String.to_charlist(Path.rootname(beam)))
    else
      _ -> :ok
    end
  end

  @spec memory_compile_time(module()) :: term() | nil
  defp memory_compile_time(module) do
    Keyword.get(module.module_info(:compile), :time)
  end

  @spec beam_compile_time(String.t()) :: {:ok, term()} | :error
  defp beam_compile_time(path) do
    case :beam_lib.chunks(String.to_charlist(path), [:compile_info]) do
      {:ok, {_mod, [compile_info: info]}} -> {:ok, Keyword.get(info, :time)}
      _ -> :error
    end
  end
end
