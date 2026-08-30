defmodule Hawk.FilterTest do
  use ExUnit.Case, async: true

  alias Hawk.Filter
  alias Videdal.Students.Reader

  describe "normalize/1" do
    test "keeps identity filters" do
      assert Filter.normalize(:all) == :all
      assert Filter.normalize(:none) == :none
    end

    test "normalizes bare map values to equality values" do
      assert Filter.normalize(%{school_id: 1, active: true, teacher_id: nil}) == %{
               school_id: {:eq, 1},
               active: {:eq, true},
               teacher_id: {:eq, nil}
             }
    end

    test "keeps explicit operator tuples" do
      filter = %{
        id: {:in, [1, 2]},
        student_id: {:neq, nil},
        enrolled_on_or_after: {:gte, ~D[2026-01-01]},
        location: {:near, %{lat: 55.6761, lng: 12.5683, radius_meters: 10_000}}
      }

      assert Filter.normalize(filter) == filter
    end

    test "normalizes nested boolean filters" do
      assert Filter.normalize({:and, %{school_id: 1}, {:or, %{active: true}, :none}}) ==
               {:and, %{school_id: {:eq, 1}}, {:or, %{active: {:eq, true}}, :none}}
    end
  end

  describe "and/2" do
    test "applies identity rules" do
      assert Filter.and(:all, %{school_id: 1}) == %{school_id: {:eq, 1}}
      assert Filter.and(%{school_id: 1}, :all) == %{school_id: {:eq, 1}}
      assert Filter.and(:none, %{school_id: 1}) == :none
      assert Filter.and(%{school_id: 1}, :none) == :none
    end

    test "merges map filters with distinct keys" do
      assert Filter.and(%{school_id: 1}, %{active: true}) == %{
               school_id: {:eq, 1},
               active: {:eq, true}
             }
    end

    test "merges map filters with identical overlapping keys" do
      assert Filter.and(%{school_id: 1}, %{school_id: 1, active: true}) == %{
               school_id: {:eq, 1},
               active: {:eq, true}
             }
    end

    test "preserves overlapping map filters that may still intersect" do
      assert Filter.and(%{country: {:in, ["DK", "NO"]}}, %{country: "DK"}) ==
               {:and, %{country: {:in, ["DK", "NO"]}}, %{country: {:eq, "DK"}}}
    end

    test "preserves conflicting overlapping map filters for query compilation" do
      assert Filter.and(%{school_id: 1}, %{school_id: 2}) ==
               {:and, %{school_id: {:eq, 1}}, %{school_id: {:eq, 2}}}
    end

    test "preserves non-map boolean structure" do
      assert Filter.and({:or, %{teacher_id: 1}, %{teacher_id: 2}}, %{active: true}) ==
               {:and, {:or, %{teacher_id: {:eq, 1}}, %{teacher_id: {:eq, 2}}}, %{active: {:eq, true}}}
    end
  end

  describe "or/2" do
    test "applies identity rules" do
      assert Filter.or(:none, %{school_id: 1}) == %{school_id: {:eq, 1}}
      assert Filter.or(%{school_id: 1}, :none) == %{school_id: {:eq, 1}}
      assert Filter.or(:all, %{school_id: 1}) == :all
      assert Filter.or(%{school_id: 1}, :all) == :all
    end

    test "preserves boolean structure" do
      assert Filter.or(%{teacher_id: 1}, %{teacher_id: 2}) ==
               {:or, %{teacher_id: {:eq, 1}}, %{teacher_id: {:eq, 2}}}
    end
  end

  describe "keys/1" do
    test "extracts keys recursively through boolean nodes" do
      filter =
        {:and, %{school_id: 1, active: true}, {:or, %{teacher_id: 2}, {:and, %{course_id: 3}, :none}}}

      assert Filter.keys(filter) == MapSet.new([:school_id, :active, :teacher_id, :course_id])
    end
  end

  describe "validate_keys!/2" do
    test "accepts filters containing only known school-domain keys" do
      filter = {:and, %{school_id: 1}, {:or, %{active: true}, %{student_id: 3}}}

      assert Filter.validate_keys!(filter, Reader.filter_keys()) == :ok
    end

    test "raises for unknown filter keys" do
      filter = %{school_id: 1, unknown_campus_id: 2}

      assert_raise ArgumentError, ~r/unknown filter key :unknown_campus_id/, fn ->
        Filter.validate_keys!(filter, Reader.filter_keys())
      end
    end
  end
end
