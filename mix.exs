defmodule Hawk.MixProject do
  use Mix.Project

  def project do
    [
      app: :hawk,
      version: "0.1.0",
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps()
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
      {:ecto, "~> 3.14"},
      {:ecto_sql, "~> 3.14"},
      {:postgrex, "~> 0.22.2"}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/videdal"]
  defp elixirc_paths(_env), do: ["lib"]
end
