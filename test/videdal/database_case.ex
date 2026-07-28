defmodule Videdal.DatabaseCase do
  @moduledoc """
  Test case for all Videdal tests.

  Checks out an Ecto SQL Sandbox transaction per test and provides `insert/2`
  and `insert!/2` factory helpers via `ExMachina`.

  Run `MIX_ENV=test mix ecto.reset` to set up the database, then `mix test`.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Ecto.Query
      import Videdal.DatabaseCase
      import Videdal.Factory

      alias Videdal.Repo
    end
  end

  setup _tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Videdal.Repo)
    :ok
  end

  def count_queries(fun) when is_function(fun, 0) do
    test_pid = self()
    ref = make_ref()
    handler_id = {__MODULE__, self(), ref}

    :telemetry.attach(
      handler_id,
      [:videdal, :repo, :query],
      &__MODULE__.handle_query_event/4,
      %{test_pid: test_pid, ref: ref, ignored_sources: ["schema_migrations"]}
    )

    try do
      result = fun.()
      {result, drain_query_count(ref, 0)}
    after
      :telemetry.detach(handler_id)
    end
  end

  def handle_query_event(_event, _measurements, metadata, %{
        test_pid: test_pid,
        ref: ref,
        ignored_sources: ignored_sources
      }) do
    unless metadata[:source] in ignored_sources do
      send(test_pid, {ref, :query})
    end
  end

  defp drain_query_count(ref, count) do
    receive do
      {^ref, :query} -> drain_query_count(ref, count + 1)
    after
      0 -> count
    end
  end
end
