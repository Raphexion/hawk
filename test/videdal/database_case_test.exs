defmodule Videdal.DatabaseCaseTest do
  use ExUnit.Case, async: true

  alias Videdal.DatabaseCase

  test "start_repo! returns the running sandbox repo pid when already started" do
    assert pid = DatabaseCase.start_repo!()
    assert is_pid(pid)
    assert Process.alive?(pid)
  end

  test "count_queries returns zero when no query events are emitted" do
    assert DatabaseCase.count_queries(fn -> :ok end) == {:ok, 0}
  end

  test "count_queries counts sandbox query telemetry and ignores schema migrations" do
    assert {:done, 1} =
             DatabaseCase.count_queries(fn ->
               :telemetry.execute(
                 [:videdal, :sandbox_repo, :query],
                 %{},
                 %{source: "courses"}
               )

               :telemetry.execute(
                 [:videdal, :sandbox_repo, :query],
                 %{},
                 %{source: "schema_migrations"}
               )

               :done
             end)
  end

  test "handle_query_event sends query messages for non-schema sources" do
    ref = make_ref()

    DatabaseCase.handle_query_event(
      [:videdal, :sandbox_repo, :query],
      %{},
      %{source: "courses"},
      %{test_pid: self(), ref: ref}
    )

    assert_received {^ref, :query}
  end

  test "handle_query_event ignores schema migration events" do
    ref = make_ref()

    DatabaseCase.handle_query_event(
      [:videdal, :sandbox_repo, :query],
      %{},
      %{source: "schema_migrations"},
      %{test_pid: self(), ref: ref}
    )

    refute_received {^ref, :query}
  end
end
