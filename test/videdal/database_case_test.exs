defmodule Videdal.DatabaseCaseTest do
  use Videdal.DatabaseCase, async: false

  alias Videdal.{DatabaseCase, Repo}

  test "count_queries returns zero when no query events are emitted" do
    assert {_, 0} = DatabaseCase.count_queries(fn -> :ok end)
  end

  test "count_queries counts repo query telemetry and ignores schema migrations" do
    assert {:done, 1} =
             DatabaseCase.count_queries(fn ->
               :telemetry.execute(
                 [:videdal, :repo, :query],
                 %{},
                 %{source: "courses"}
               )

               :telemetry.execute(
                 [:videdal, :repo, :query],
                 %{},
                 %{source: "schema_migrations"}
               )

               :done
             end)
  end

  test "handle_query_event sends query messages for non-schema sources" do
    ref = make_ref()

    DatabaseCase.handle_query_event(
      [:videdal, :repo, :query],
      %{},
      %{source: "courses"},
      %{test_pid: self(), ref: ref, ignored_sources: ["schema_migrations"]}
    )

    assert_received {^ref, :query}
  end

  test "handle_query_event ignores schema migration events" do
    ref = make_ref()

    DatabaseCase.handle_query_event(
      [:videdal, :repo, :query],
      %{},
      %{source: "schema_migrations"},
      %{test_pid: self(), ref: ref, ignored_sources: ["schema_migrations"]}
    )

    refute_received {^ref, :query}
  end

  test "the sandbox is checked out and a query works" do
    assert Repo.all(Videdal.School) == []
  end
end
