import Config

config :hawk, ecto_repos: [Videdal.SandboxRepo]

repo_config =
  case System.get_env("HAWK_DATABASE_URL") do
    nil ->
      [
        database: "hawk_test",
        hostname: "localhost",
        pool: Ecto.Adapters.SQL.Sandbox,
        telemetry_prefix: [:videdal, :sandbox_repo],
        log: false
      ]

    database_url ->
      [
        url: database_url,
        pool: Ecto.Adapters.SQL.Sandbox,
        telemetry_prefix: [:videdal, :sandbox_repo],
        log: false
      ]
  end

config :hawk, Videdal.SandboxRepo, repo_config
