defmodule Hawk.MixProject do
  use Mix.Project

  def project do
    [
      app: :hawk,
      version: "0.3.0",
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: dialyzer(),
      aliases: aliases(),
      test_coverage: [
        summary: [threshold: 85],
        # Cover only the Hawk library itself. The Videdal example app and the
        # Hawk.Test* helpers are compiled under `elixirc_paths(:test)` to
        # exercise Hawk, but they are test fixtures, not shipped code.
        ignore_modules: [~r/^Videdal\b/, Hawk.TestConn, Hawk.TestSocket]
      ]
    ]
  end

  def cli do
    [
      preferred_envs: [
        "ecto.create": :test,
        "ecto.drop": :test,
        "ecto.migrate": :test,
        "ecto.rollback": :test,
        "ecto.setup": :test,
        "ecto.reset": :test
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      # Hawk provides reusable Ecto/PostgreSQL infrastructure, but host
      # applications own their concrete Repo modules and database config.
      {:ecto, ">= 3.5.0 and < 4.0.0"},
      {:ecto_sql, ">= 3.5.0 and < 4.0.0"},
      {:postgrex, ">= 0.15.0 and < 1.0.0"},
      {:telemetry, "~> 1.0"},
      # Phoenix is a required dependency: Hawk generates JSON:API controllers and
      # LiveView helpers that call Phoenix/Plug directly. Host applications still
      # own their Repo, authentication, and supervision tree.
      {:phoenix, "~> 1.7"},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_ecto, "~> 4.0"},
      {:jason, "~> 1.4"},
      # Test factories
      {:ex_machina, "~> 2.8", only: :test},
      # Code quality
      {:dialyxir, "~> 1.3", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/videdal", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp aliases do
    [
      "ecto.setup": ["ecto.create --quiet", "ecto.migrate --quiet"],
      "ecto.reset": ["ecto.drop --quiet", "ecto.setup"],
      # `mix test` is the complete local gate: validate every Hawk resource's
      # contract, then run the full suite.
      test: ["hawk.validate", "test"]
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:ex_unit, :mix],
      ignore_warnings: "dialyzer_ignore.exs",
      list_unused_filters: true,
      plt_local_path: "priv/plts/project.plt",
      plt_core_path: "priv/plts/core.plt"
    ]
  end
end
