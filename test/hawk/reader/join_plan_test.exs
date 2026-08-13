defmodule Hawk.Reader.JoinPlanTest do
  use ExUnit.Case, async: true

  alias Hawk.Reader.JoinPlan

  defp rule(overrides) do
    Map.merge(
      %{
        name: :school,
        when_filter: MapSet.new([:school_name]),
        when_sort: MapSet.new(),
        preserves_roots: false,
        apply: &Function.identity/1
      },
      Map.new(overrides)
    )
  end

  test "rejects a non-preserving attach when some OR paths do not require it" do
    filter = {:or, %{school_name: "A"}, %{student_id: 1}}

    assert_raise ArgumentError, ~r/unsafe reader attach :school.*\[:school_name\].*\[:student_id\]/, fn ->
      JoinPlan.apply(Ecto.Queryable.to_query(Videdal.Student), [rule([])], filter, [])
    end
  end

  test "allows an attach required by an enclosing conjunction" do
    filter =
      {:and, %{school_name: "required"}, {:or, %{school_name: "alternative"}, %{student_id: 1}}}

    assert %Ecto.Query{} =
             JoinPlan.apply(Ecto.Queryable.to_query(Videdal.Student), [rule([])], filter, [])
  end

  test "treats none as requiring every attach because it cannot match roots" do
    filter = {:or, %{school_name: "A"}, :none}

    assert %Ecto.Query{} =
             JoinPlan.apply(Ecto.Queryable.to_query(Videdal.Student), [rule([])], filter, [])
  end

  test "rejects all as a path that does not require the attach" do
    filter = {:or, %{school_name: "A"}, :all}

    assert_raise ArgumentError, ~r/unsafe reader attach :school/, fn ->
      JoinPlan.apply(Ecto.Queryable.to_query(Videdal.Student), [rule([])], filter, [])
    end
  end

  test "allows a root-preserving attach regardless of OR paths" do
    filter = {:or, %{school_name: "A"}, %{student_id: 1}}

    assert %Ecto.Query{} =
             JoinPlan.apply(
               Ecto.Queryable.to_query(Videdal.Student),
               [rule(preserves_roots: true)],
               filter,
               []
             )
  end

  test "does not apply OR safety to a rule activated only by sorting" do
    sort_rule =
      rule(
        when_filter: MapSet.new(),
        when_sort: MapSet.new([:school_name])
      )

    filter = {:or, %{active: true}, %{student_id: 1}}

    assert %Ecto.Query{} =
             JoinPlan.apply(
               Ecto.Queryable.to_query(Videdal.Student),
               [sort_rule],
               filter,
               :school_name
             )
  end

  test "still rejects an unsafe filter when sorting activates the same rule" do
    filter_and_sort_rule = rule(when_sort: MapSet.new([:school_name]))
    filter = {:or, %{school_name: "A"}, %{student_id: 1}}

    assert_raise ArgumentError, ~r/unsafe reader attach :school/, fn ->
      JoinPlan.apply(
        Ecto.Queryable.to_query(Videdal.Student),
        [filter_and_sort_rule],
        filter,
        :school_name
      )
    end
  end
end
