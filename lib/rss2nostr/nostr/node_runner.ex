defmodule Rss2Nostr.Nostr.NodeRunner do
  @moduledoc false

  @doc """
  Runs a Node script with JSON on stdin via a mode-0600 temp file.

  The helpers under `priv/*.mjs` also accept stdin; we use a private temp file
  because `System.cmd/3` cannot close stdin after writing without a NIF helper.
  """
  @spec run(String.t(), iodata()) :: {:ok, String.t()} | {:error, String.t()}
  def run(script, input) when is_binary(script) do
    dir = Path.join(System.tmp_dir!(), "rss2nostr-#{System.pid()}")
    File.mkdir_p!(dir)
    _ = File.chmod(dir, 0o700)

    path =
      Path.join(dir, "input-#{:erlang.unique_integer([:positive])}-#{System.unique_integer([:positive])}.json")

    try do
      write_private!(path, IO.iodata_to_binary(input))

      case System.cmd("node", [script],
             cd: Path.dirname(script),
             stderr_to_stdout: true,
             env: [{"INPUT_FILE", path}]
           ) do
        {output, 0} ->
          {:ok, output}

        {output, _code} ->
          {:error, output}
      end
    after
      _ = File.rm(path)
    end
  end

  @spec write_private!(String.t(), binary()) :: :ok
  defp write_private!(path, content) do
    case File.open(path, [:write, :exclusive, :raw, :binary]) do
      {:ok, io} ->
        try do
          _ = File.chmod(path, 0o600)
          IO.binwrite(io, content)
        after
          File.close(io)
        end

      {:error, reason} ->
        raise File.Error, reason: reason, action: "open", path: path
    end
  end
end
