import Config

config :hawk, ecto_repos: [Videdal.Repo]

repo_config =
  case System.get_env("HAWK_DATABASE_URL") do
    nil ->
      [
        database: "hawk_test",
        hostname: "localhost",
        pool: Ecto.Adapters.SQL.Sandbox,
        types: Videdal.PostgresTypes,
        telemetry_prefix: [:videdal, :repo],
        log: false
      ]

    database_url ->
      [
        url: database_url,
        pool: Ecto.Adapters.SQL.Sandbox,
        types: Videdal.PostgresTypes,
        telemetry_prefix: [:videdal, :repo],
        log: false
      ]
  end

config :hawk, Videdal.Repo, repo_config
