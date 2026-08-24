defmodule Rss2Nostr.CLI.Output do
  @moduledoc """
  Helper functions for CLI output formatting.
  """

  @doc """
  Prints an info message.
  """
  @spec info(String.t()) :: :ok
  def info(message) do
    IO.puts(message)
  end

  @doc """
  Prints a success message in green.
  """
  @spec success(String.t()) :: :ok
  def success(message) do
    IO.puts(IO.ANSI.green() <> message <> IO.ANSI.reset())
  end

  @doc """
  Prints a warning message in yellow.
  """
  @spec warning(String.t()) :: :ok
  def warning(message) do
    IO.puts(IO.ANSI.yellow() <> "Warning: " <> message <> IO.ANSI.reset())
  end

  @doc """
  Prints an error message in red.
  """
  @spec error(String.t()) :: :ok
  def error(message) do
    IO.puts(IO.ANSI.red() <> "Error: " <> message <> IO.ANSI.reset())
  end

  @doc """
  Prints a debug message in cyan (only in dev).
  """
  @spec debug(String.t()) :: :ok
  def debug(message) do
    if Mix.env() == :dev do
      IO.puts(IO.ANSI.cyan() <> "Debug: " <> message <> IO.ANSI.reset())
    end
  end
end
