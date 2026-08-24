defmodule Rss2Nostr.MixProject do
  use Mix.Project

  def project do
    [
      app: :rss2nostr,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      escript: escript(),
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        plt_add_apps: [:mix, :ex_unit]
      ],
      releases: releases()
    ]
  end

  defp releases do
    [
      rss2nostr: [
        include_executables_for: [:unix],
        applications: [runtime_tools: :permanent]
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger, :runtime_tools, :inets, :ex_mcp],
      mod: {Rss2Nostr.Application, []}
    ]
  end

  defp deps do
    [
      # Database
      {:ecto_sql, "~> 3.14"},
      {:postgrex, "~> 0.22"},

      # HTTP & WebSocket
      {:req, "~> 0.7"},
      {:websockex, "~> 0.4"},
      # tzdata still depends on hackney ~> 1.17; force the patched 4.x line.
      # App HTTP goes through Req; tzdata uses Rss2Nostr.TzdataHTTPClient.
      {:hackney, "~> 4.7", override: true},

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

      # Web Server / Phoenix LiveView
      {:plug, "~> 1.15"},
      {:bandit, "~> 1.12"},
      {:phoenix, "~> 1.8"},
      {:phoenix_html, "~> 4.2"},
      {:phoenix_live_view, "~> 1.1"},
      {:phoenix_live_reload, "~> 1.6", only: :dev},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},

      # MCP (AI management)
      {:ex_mcp, "~> 1.0.0-rc.6"},

      # Utilities
      {:timex, "~> 3.7"},
      {:cachex, "~> 3.6"},
      {:dotenvy, "~> 1.1"},

      # Development & Code Quality
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      "assets.setup": ["esbuild.install --if-missing"],
      "assets.build": ["esbuild rss2nostr"],
      "assets.deploy": ["esbuild rss2nostr --minify"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      dev: ["ecto.create --quiet", "ecto.migrate --quiet", "rss2nostr.server"],
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
