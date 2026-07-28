defmodule Videdal.Repo do
  @moduledoc """
  Real Ecto repo used by all Videdal tests.

  Hawk's library code does not depend on this module. It exists so the test
  suite can exercise readers, writers, and controllers against real PostgreSQL.
  """

  use Ecto.Repo,
    otp_app: :hawk,
    adapter: Ecto.Adapters.Postgres
end
