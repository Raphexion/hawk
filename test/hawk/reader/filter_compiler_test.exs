defmodule Hawk.Reader.FilterCompilerTest do
  use ExUnit.Case, async: true

  alias Hawk.Reader.FilterCompiler
  alias Videdal.Student

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
      assert_query(compile(%{id: {:in, [1, 2, 3]}}), "s0.id in ^[1, 2, 3]")
      assert_query(compile(%{id: {:in, []}}), "where: false")
      assert compile(%{id: {:not_in, []}}).wheres == []
      assert_query(compile(%{id: {:not_in, [1, 2]}}), "s0.id not in ^[1, 2]")
    end

    test "compiles comparison operators" do
      assert_query(compile(%{id: {:lt, 10}}), "s0.id < ^10")
      assert_query(compile(%{id: {:lte, 10}}), "s0.id <= ^10")
      assert_query(compile(%{id: {:gt, 10}}), "s0.id > ^10")
      assert_query(compile(%{id: {:gte, 10}}), "s0.id >= ^10")
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

    test "raises for fields that are not on the schema" do
      assert_raise ArgumentError, ~r/unknown field :campus_id for Videdal.Student/, fn ->
        compile(%{campus_id: 1})
      end
    end

    test "raises for unsupported operators" do
      assert_raise ArgumentError, ~r/unsupported filter operator :starts_with/, fn ->
        compile(%{name: {:starts_with, "Ada"}})
      end
    end
  end

  defp compile(filter) do
    FilterCompiler.compile(Student, Student, filter)
  end

  defp assert_query(query, expected) do
    assert inspect(query) =~ expected
  end
end
