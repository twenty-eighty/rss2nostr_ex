defmodule Rss2Nostr.Release do
  @moduledoc """
  Used for executing DB release tasks, such as migrations, inside a release.
  """

  @app :rss2nostr

  def migrate do
    load_app()

    for repo <- Application.fetch_env!(@app, :ecto_repos) do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  defp load_app do
    Application.load(@app)
    Application.ensure_all_started(:ssl)
  end
end
