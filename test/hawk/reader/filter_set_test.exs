defmodule Hawk.Reader.FilterSetTest.Policy do
  @moduledoc false

  def read_filter(_authority), do: :all
end

defmodule Hawk.Reader.FilterSetTest.StudentIdentityFilters do
  @moduledoc false

  use Hawk.Reader.FilterSet, schema: Videdal.Student

  filter :student_id do
    fn value ->
      student_id = equality_operand!(value, :student_id)
      dynamic([root: student], student.id == ^student_id)
    end
  end

  filter :activity, value: :object do
    fn {:eq, %{"active" => active}} ->
      dynamic([root: student], student.active == ^active)
    end
  end

  defp equality_operand!({:eq, value}, _filter), do: value
  defp equality_operand!(value, _filter) when is_binary(value), do: value

  defp equality_operand!({operator, _value}, filter) do
    raise ArgumentError, "filter operator #{inspect(operator)} is not supported for #{filter}"
  end
end

defmodule Hawk.Reader.FilterSetTest.StudentSchoolFilters do
  @moduledoc false

  use Hawk.Reader.FilterSet, schema: Videdal.Student

  attach :school, when_filter: [:school_name], preserves_roots: true do
    join(query, :left, [root: student], school in assoc(student, :school), as: :school)
  end

  filter :school_name do
    fn value ->
      school_name = equality_operand!(value, :school_name)
      dynamic([school: school], school.name == ^school_name)
    end
  end

  defp equality_operand!({:eq, value}, _filter), do: value
  defp equality_operand!(value, _filter) when is_binary(value), do: value

  defp equality_operand!({operator, _value}, filter) do
    raise ArgumentError, "filter operator #{inspect(operator)} is not supported for #{filter}"
  end
end

defmodule Hawk.Reader.FilterSetTest.Reader do
  @moduledoc false

  use Hawk.Reader.Resource,
    repo: Videdal.Repo,
    schema: Videdal.Student,
    policy: Hawk.Reader.FilterSetTest.Policy

  filter(:active)

  import_filters(Hawk.Reader.FilterSetTest.StudentIdentityFilters)
  import_filters(Hawk.Reader.FilterSetTest.StudentSchoolFilters)

  sort(:id)
end

defmodule Hawk.Reader.FilterSetTest do
  use Videdal.DatabaseCase, async: true

  import Ecto.Query, only: [from: 2]

  alias Hawk.Authority
  alias Hawk.Reader.FilterSetTest.Reader
  alias Hawk.Reader.FilterSetTest.StudentIdentityFilters
  alias Hawk.Reader.FilterSetTest.StudentSchoolFilters

  test "applies a filter set independently to an existing query" do
    matching_school = insert(:school, name: "Videdal School")
    other_school = insert(:school, name: "Other School")
    matching_student = insert(:student, school_id: matching_school.id)
    insert(:student, school_id: other_school.id)

    results =
      Videdal.Student
      |> from(as: :root)
      |> StudentSchoolFilters.apply_to(%{school_name: "Videdal School"})
      |> Videdal.Repo.all()

    assert Enum.map(results, & &1.id) == [matching_student.id]
  end

  test "applies an object-valued filter set handler independently" do
    school = insert(:school)
    matching_student = insert(:student, school_id: school.id, active: true)
    insert(:student, school_id: school.id, active: false)

    results =
      Videdal.Student
      |> from(as: :root)
      |> StudentIdentityFilters.apply_to(%{activity: %{"active" => true}})
      |> Videdal.Repo.all()

    assert Enum.map(results, & &1.id) == [matching_student.id]
    assert StudentIdentityFilters.__hawk_filter_set__().filter_value_types == %{activity: :object}
  end

  test "keeps custom filter helpers local to the filter set" do
    school = insert(:school)
    student = insert(:student, school_id: school.id)

    results =
      Videdal.Student
      |> from(as: :root)
      |> StudentIdentityFilters.apply_to(%{student_id: {:eq, student.id}})
      |> Videdal.Repo.all()

    assert Enum.map(results, & &1.id) == [student.id]

    assert_raise ArgumentError, ~r/operator :in is not supported for student_id/, fn ->
      Videdal.Student
      |> from(as: :root)
      |> StudentIdentityFilters.apply_to(%{student_id: {:in, [student.id]}})
    end
  end

  test "rejects filters not owned by the isolated filter set" do
    assert_raise ArgumentError, ~r/unknown filter key :active/, fn ->
      Videdal.Student
      |> from(as: :root)
      |> StudentIdentityFilters.apply_to(%{active: true})
    end
  end

  test "an unchanged reader observes a recompiled filter set" do
    module_suffix = System.unique_integer([:positive])
    filter_set = Module.concat(Hawk.Reader.FilterSetTest, "ReloadFilters#{module_suffix}")
    reader = Module.concat(Hawk.Reader.FilterSetTest, "ReloadReader#{module_suffix}")

    compile_reload_filter_set(filter_set, :id, [], true)
    compile_reload_reader(reader, filter_set)

    school = insert(:school)
    student = insert(:student, school_id: school.id)

    assert apply(reader, :filter_keys, []) == MapSet.new([:reload_lookup])
    assert apply(reader, :filter_value_types, []) == %{reload_lookup: :object}

    assert [found] =
             apply(reader, :all, [
               [authority: Authority.system(), filter: %{reload_lookup: %{"value" => student.id}}]
             ])

    assert found.id == student.id

    ExUnit.CaptureIO.capture_io(:stderr, fn ->
      compile_reload_filter_set(filter_set, :school_id, [:active])
    end)

    assert apply(reader, :filter_keys, []) == MapSet.new([:active, :reload_lookup])
    assert apply(reader, :filter_value_types, []) == %{}
    assert [found] = apply(reader, :all, [[authority: Authority.system(), filter: %{reload_lookup: school.id}]])
    assert found.id == student.id
  end

  test "exposes imported filters through the reader metadata" do
    assert Reader.filter_keys() == MapSet.new([:active, :activity, :school_name, :student_id])
    assert Map.has_key?(Reader.filter_handlers(), :school_name)
    assert Map.has_key?(Reader.filter_handlers(), :student_id)
    assert Reader.filter_value_types() == %{activity: :object}
    assert [%{name: :school, preserves_roots: true}] = Reader.join_plan()
  end

  test "preserves a cross-set OR when attach rules retain unmatched roots" do
    matching_school = insert(:school, name: "Videdal School")
    other_school = insert(:school, name: "Other School")
    school_match = insert(:student, school_id: matching_school.id)
    identity_match = insert(:student, school_id: nil)
    insert(:student, school_id: other_school.id)

    filter =
      {:or, %{school_name: "Videdal School"}, %{student_id: identity_match.id}}

    results = Reader.all(authority: Authority.system(), filter: filter)

    assert MapSet.new(results, & &1.id) == MapSet.new([school_match.id, identity_match.id])
  end

  test "rejects an unsafe OR when applying a filter set independently" do
    module_suffix = System.unique_integer([:positive])
    filter_set = Module.concat(Hawk.Reader.FilterSetTest, "UnsafeFilters#{module_suffix}")

    Code.compile_string("""
    defmodule #{inspect(filter_set)} do
      use Hawk.Reader.FilterSet, schema: Videdal.Student

      filter(:active)

      attach :school, when_filter: [:school_name] do
        join(query, :inner, [root: student], school in assoc(student, :school), as: :school)
      end

      filter :school_name do
        fn {:eq, school_name} -> dynamic([school: school], school.name == ^school_name) end
      end
    end
    """)

    filter = {:or, %{school_name: "Videdal School"}, %{active: true}}

    assert_raise ArgumentError, ~r/unsafe reader attach :school/, fn ->
      query = from(Videdal.Student, as: :root)
      Kernel.apply(filter_set, :apply_to, [query, filter])
    end
  end

  test "composes imported filters with resource-local filters" do
    school = insert(:school, name: "Videdal School")
    active_student = insert(:student, school_id: school.id, active: true)
    insert(:student, school_id: school.id, active: false)

    results =
      Reader.all(
        authority: Authority.system(),
        filter: %{school_name: "Videdal School", active: true}
      )

    assert Enum.map(results, & &1.id) == [active_student.id]
  end

  test "rejects invalid filter set attach options" do
    module_suffix = System.unique_integer([:positive])

    assert_raise ArgumentError, ~r/unknown filter set attach option :preserve_roots/, fn ->
      Code.compile_string("""
      defmodule Hawk.Reader.FilterSetTest.InvalidAttach#{module_suffix} do
        use Hawk.Reader.FilterSet, schema: Videdal.Student

        attach :school, when_filter: [:school_name], preserve_roots: true do
          query
        end
      end
      """)
    end
  end

  test "rejects sort-triggered attach rules because sorting belongs to the reader" do
    module_suffix = System.unique_integer([:positive])

    assert_raise ArgumentError, ~r/filter set attach :school cannot use :when_sort/, fn ->
      Code.compile_string("""
      defmodule Hawk.Reader.FilterSetTest.SortFilters#{module_suffix} do
        use Hawk.Reader.FilterSet, schema: Videdal.Student

        attach :school, when_filter: [], when_sort: [:school_name] do
          query
        end
      end
      """)
    end
  end

  test "rejects duplicate filters across a reader and an imported filter set" do
    module_suffix = System.unique_integer([:positive])

    assert_raise ArgumentError, ~r/duplicate reader filter :student_id/, fn ->
      Code.compile_string("""
      defmodule Hawk.Reader.FilterSetTest.DuplicateFilters#{module_suffix} do
        use Hawk.Reader.FilterSet, schema: Videdal.Student
        filter(:student_id)
      end

      defmodule Hawk.Reader.FilterSetTest.DuplicateReader#{module_suffix} do
        use Hawk.Reader.Resource,
          repo: Videdal.Repo,
          schema: Videdal.Student,
          policy: Hawk.Reader.FilterSetTest.Policy

        filter(:student_id)
        import_filters(Hawk.Reader.FilterSetTest.DuplicateFilters#{module_suffix})
      end
      """)
    end
  end

  test "rejects a filter set for a different schema" do
    module_suffix = System.unique_integer([:positive])

    assert_raise ArgumentError, ~r/filter set .* uses Videdal.Student, expected Videdal.Course/, fn ->
      Code.compile_string("""
      defmodule Hawk.Reader.FilterSetTest.StudentFilters#{module_suffix} do
        use Hawk.Reader.FilterSet, schema: Videdal.Student
        filter(:student_id)
      end

      defmodule Hawk.Reader.FilterSetTest.CourseReader#{module_suffix} do
        use Hawk.Reader.Resource,
          repo: Videdal.Repo,
          schema: Videdal.Course,
          policy: Hawk.Reader.FilterSetTest.Policy

        import_filters(Hawk.Reader.FilterSetTest.StudentFilters#{module_suffix})
      end
      """)
    end
  end

  defp compile_reload_filter_set(module, field, direct_filters, object? \\ false) do
    declarations = Enum.map_join(direct_filters, "\n", &"filter(#{inspect(&1)})")

    filter_declaration =
      if object? do
        """
        filter :reload_lookup, value: :object do
          fn {:eq, %{"value" => value}} ->
            dynamic([root: student], field(student, #{inspect(field)}) == ^value)
          end
        end
        """
      else
        """
        filter :reload_lookup do
          fn {:eq, value} -> dynamic([root: student], field(student, #{inspect(field)}) == ^value) end
        end
        """
      end

    Code.compile_string("""
    defmodule #{inspect(module)} do
      use Hawk.Reader.FilterSet, schema: Videdal.Student

      #{filter_declaration}

      #{declarations}
    end
    """)
  end

  defp compile_reload_reader(module, filter_set) do
    Code.compile_string("""
    defmodule #{inspect(module)} do
      use Hawk.Reader.Resource,
        repo: Videdal.Repo,
        schema: Videdal.Student,
        policy: Hawk.Reader.FilterSetTest.Policy

      import_filters(#{inspect(filter_set)})
    end
    """)
  end
end
