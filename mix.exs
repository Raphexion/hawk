defmodule Hawk.MixProject do
  use Mix.Project

  def project do
    [
      app: :hawk,
      version: "0.1.0",
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: dialyzer()
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
      # Code quality
      {:dialyxir, "~> 1.3", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/videdal"]
  defp elixirc_paths(_env), do: ["lib"]

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
