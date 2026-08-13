defmodule Hawk.Reader.FilterCompilerTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Hawk.Reader.FilterCompiler
  alias Videdal.{Grade, Student}

  describe "compile/3" do
    test "leaves all filters unconstrained" do
      query = compile(:all)

      assert query.wheres == []
    end

    test "compiles none filters to a false predicate" do
      query = compile(:none)

      assert_query(query, "where: false")
    end

    test "compiles bare map values as equality predicates" do
      query = compile(%{name: "Ada", active: true})

      assert_query(query, ~s(s0.name == ^"Ada"))
      assert_query(query, "s0.active == ^true")
    end

    test "compiles nil equality with null-safe semantics" do
      query = compile(%{school_id: nil})

      assert_query(query, "is_nil(s0.school_id)")
    end

    test "compiles nil inequality with null-safe semantics" do
      query = compile(%{school_id: {:neq, nil}})

      assert_query(query, "not is_nil(s0.school_id)")
    end

    test "compiles list operators with deterministic empty-list behavior" do
      assert_query(compile_grade(%{score: {:in, [1, 2, 3]}}), "g0.score in ^[1, 2, 3]")
      assert_query(compile_grade(%{score: {:in, []}}), "where: false")
      assert compile_grade(%{score: {:not_in, []}}).wheres == []
      assert_query(compile_grade(%{score: {:not_in, [1, 2]}}), "g0.score not in ^[1, 2]")
    end

    test "compiles integer comparison operators" do
      assert_query(compile_grade(%{score: {:lt, 10}}), "g0.score < ^10")
      assert_query(compile_grade(%{score: {:lte, 10}}), "g0.score <= ^10")
      assert_query(compile_grade(%{score: {:gt, 10}}), "g0.score > ^10")
      assert_query(compile_grade(%{score: {:gte, 10}}), "g0.score >= ^10")
    end

    test "casts integer filter operands before compiling the query" do
      assert_query(compile_grade(%{score: "2"}), "g0.score == ^2")
      assert_query(compile_grade(%{score: {:gt, "5"}}), "g0.score > ^5")
      assert_query(compile_grade(%{score: {:in, ["2", "5"]}}), "g0.score in ^[2, 5]")
    end

    test "rejects invalid integer operands and operators" do
      assert_raise ArgumentError, ~s(invalid integer filter value "many" for field :score), fn ->
        compile_grade(%{score: {:gt, "many"}})
      end

      assert_raise ArgumentError,
                   "filter operator :in requires a list for integer field :score",
                   fn ->
                     compile_grade(%{score: {:in, "2"}})
                   end

      assert_raise ArgumentError,
                   "filter operator :ilike is not supported for integer field :score",
                   fn ->
                     compile_grade(%{score: {:ilike, "2%"}})
                   end
    end

    test "compiles text matching operators" do
      assert_query(compile(%{name: {:like, "Ada%"}}), ~s"like(s0.name, ^\"Ada%\")")
      assert_query(compile(%{name: {:ilike, "ada%"}}), ~s"ilike(s0.name, ^\"ada%\")")
    end

    test "preserves boolean AST composition" do
      query = compile({:or, %{name: "Ada"}, {:and, %{active: true}, %{school_id: 7}}})

      assert_query(query, ~s(s0.name == ^"Ada"))
      assert_query(query, "or")
      assert_query(query, "s0.active == ^true")
      assert_query(query, "and")
      assert_query(query, "s0.school_id == ^7")
    end

    test "uses custom handlers before falling back to schema fields" do
      handlers = %{
        student_id: fn {:eq, student_id} ->
          dynamic([student], student.id == ^student_id)
        end
      }

      query = FilterCompiler.compile(Student, Student, %{student_id: 12}, handlers)

      assert_query(query, "s0.id == ^12")
    end

    test "composes custom handlers with direct field filters" do
      handlers = %{
        student_id: fn {:eq, student_id} ->
          dynamic([student], student.id == ^student_id)
        end
      }

      query = FilterCompiler.compile(Student, Student, %{student_id: 12, active: true}, handlers)

      assert_query(query, "s0.id == ^12")
      assert_query(query, "s0.active == ^true")
    end

    test "rejects an attach-triggering handler that expands to all" do
      handlers = %{school_name: fn _value -> :all end}

      assert_raise ArgumentError, ~r/attach trigger filter :school_name returned :all/, fn ->
        FilterCompiler.compile(
          Student,
          Student,
          %{school_name: "A"},
          handlers,
          %{},
          MapSet.new([:school_name])
        )
      end
    end

    test "allows a non-triggering handler to expand to all" do
      handlers = %{noop: fn _value -> :all end}

      query = FilterCompiler.compile(Student, Student, %{noop: true}, handlers)

      assert query.wheres == []
    end

    test "raises when a handler returns an unsupported value" do
      handlers = %{student_id: fn _value -> :bad end}

      assert_raise ArgumentError,
                   ~r/filter handler :student_id returned unsupported value :bad/,
                   fn ->
                     FilterCompiler.compile(Student, Student, %{student_id: 12}, handlers)
                   end
    end

    test "raises for fields that are not on the schema" do
      assert_raise ArgumentError, ~r/unknown field :campus_id for Videdal.Student/, fn ->
        compile(%{campus_id: 1})
      end
    end

    test "raises for unsupported operators" do
      assert_raise ArgumentError, ~r/unsupported filter operator :starts_with/, fn ->
        compile(%{name: {:starts_with, "Ada"}})
      end

      near = {:near, %{lat: 55.6761, lng: 12.5683, radius_meters: 10_000}}

      assert_raise ArgumentError,
                   "filter operator :near requires a declared coordinate filter for field :name",
                   fn -> compile(%{name: near}) end

      assert_raise ArgumentError,
                   "filter operator :near requires a declared coordinate filter for field :student_id",
                   fn ->
                     FilterCompiler.compile(
                       Student,
                       Student,
                       %{student_id: near},
                       %{student_id: fn _value -> :all end}
                     )
                   end
    end
  end

  defp compile(filter) do
    FilterCompiler.compile(Student, Student, filter)
  end

  defp compile_grade(filter) do
    FilterCompiler.compile(Grade, Grade, filter)
  end

  defp assert_query(query, expected) do
    assert inspect(query) =~ expected
  end
end
