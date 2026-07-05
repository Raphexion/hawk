defmodule Videdal.SandboxRepo do
  @moduledoc """
  Real Ecto repo used only by opt-in Videdal integration tests.

  Hawk's library code does not depend on this module. It exists so the example
  application can prove batching and query-count behavior against PostgreSQL
  without forcing a concrete repo on host applications.
  """

  use Ecto.Repo,
    otp_app: :hawk,
    adapter: Ecto.Adapters.Postgres
end
