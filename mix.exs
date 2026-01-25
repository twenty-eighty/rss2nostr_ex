defmodule Rss2Nostr.MixProject do
  use Mix.Project

  def project do
    [
      app: :rss2nostr,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      escript: escript(),
      elixirc_paths: elixirc_paths(Mix.env()),
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        plt_add_apps: [:mix, :ex_unit]
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger, :runtime_tools, :inets],
      mod: {Rss2Nostr.Application, []}
    ]
  end

  defp deps do
    [
      # Database
      {:ecto_sql, "~> 3.11"},
      {:postgrex, "~> 0.17"},

      # HTTP & WebSocket
      {:httpoison, "~> 2.2"},
      {:websockex, "~> 0.4"},

      # Parsing
      {:floki, "~> 0.36"},
      {:sweet_xml, "~> 0.7"},
      {:jason, "~> 1.4"},

      # Nostr / Cryptography
      {:bech32, "~> 1.0"},
      # secp256k1 / BIP340 Schnorr
      {:k256, "~> 0.0.8"},

      # CLI
      {:optimus, "~> 0.3"},

      # Web Server
      {:plug, "~> 1.15"},
      {:bandit, "~> 1.2"},

      # Utilities
      {:timex, "~> 3.7"},
      {:cachex, "~> 3.6"},

      # Development & Code Quality
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      # Code quality checks
      quality: ["format --check-formatted", "credo --strict", "dialyzer"],
      lint: ["credo --strict"],
      typecheck: ["dialyzer"]
    ]
  end

  defp escript do
    [main_module: Rss2Nostr.CLI]
  end
end
