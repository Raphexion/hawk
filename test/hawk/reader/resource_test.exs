defmodule Hawk.Reader.ResourceTest.Policy do
  @moduledoc false

  def read_filter(_authority), do: :all
end

defmodule Hawk.Reader.ResourceTest.Reader do
  @moduledoc false

  use Hawk.Reader.Resource,
    repo: Videdal.Repo,
    schema: Videdal.Student,
    policy: Hawk.Reader.ResourceTest.Policy

  filter(:id)
  filter(:school_id)
  filter(:active)

  filter :activity, value: :object do
    fn {:eq, %{"active" => active}} ->
      dynamic([root: student], student.active == ^active)
    end
  end

  preload(:school)

  filter :student_id do
    fn {:eq, student_id} ->
      dynamic([student], student.id == ^student_id)
    end
  end

  attach :school, when_filter: [:school_name], when_sort: [:school_name] do
    join(query, :inner, [root: student], school in assoc(student, :school), as: :school)
  end

  filter :school_name do
    fn {:eq, school_name} ->
      dynamic([school: school], school.name == ^school_name)
    end
  end
end

defmodule Hawk.Reader.ResourceTest.PreservingReader do
  @moduledoc false

  use Hawk.Reader.Resource,
    repo: Videdal.Repo,
    schema: Videdal.Student,
    policy: Hawk.Reader.ResourceTest.Policy

  filter :student_id do
    fn {:eq, student_id} ->
      dynamic([root: student], student.id == ^student_id)
    end
  end

  attach :school, when_filter: [:school_name], preserves_roots: true do
    join(query, :left, [root: student], school in assoc(student, :school), as: :school)
  end

  filter :school_name do
    fn {:eq, school_name} ->
      dynamic([school: school], school.name == ^school_name)
    end
  end
end

defmodule Hawk.Reader.ResourceTest.SchoolPolicy do
  @moduledoc false

  def read_filter(_authority), do: %{school_name: "Videdal School"}
end

defmodule Hawk.Reader.ResourceTest.PolicySchoolReader do
  @moduledoc false

  use Hawk.Reader.Resource,
    repo: Videdal.Repo,
    schema: Videdal.Student,
    policy: Hawk.Reader.ResourceTest.SchoolPolicy

  filter :student_id do
    fn {:eq, student_id} -> dynamic([root: student], student.id == ^student_id) end
  end

  attach :school, when_filter: [:school_name] do
    join(query, :inner, [root: student], school in assoc(student, :school), as: :school)
  end

  filter :school_name do
    fn {:eq, school_name} -> dynamic([school: school], school.name == ^school_name) end
  end
end

defmodule Hawk.Reader.ResourceTest.ForcedSchoolReader do
  @moduledoc false

  use Hawk.Reader.Resource,
    repo: Videdal.Repo,
    schema: Videdal.Student,
    policy: Hawk.Reader.ResourceTest.Policy,
    forced_filter: %{school_name: "Videdal School"}

  filter :student_id do
    fn {:eq, student_id} ->
      dynamic([root: student], student.id == ^student_id)
    end
  end

  attach :school, when_filter: [:school_name] do
    join(query, :inner, [root: student], school in assoc(student, :school), as: :school)
  end

  filter :school_name do
    fn {:eq, school_name} ->
      dynamic([school: school], school.name == ^school_name)
    end
  end
end

defmodule Hawk.Reader.ResourceTest.CountReader do
  @moduledoc false

  use Hawk.Reader.Resource,
    repo: Videdal.Repo,
    schema: Videdal.Student,
    policy: Hawk.Reader.ResourceTest.Policy

  filter(:id)
  sort(:parent_student_id)

  attach :parent_students, when_sort: [:parent_student_id] do
    join(query, :inner, [root: student], parent_student in assoc(student, :parent_students), as: :parent_student)
  end
end

defmodule Hawk.Reader.ResourceTest.MultiplyingCountReader do
  @moduledoc false

  use Hawk.Reader.Resource,
    repo: Videdal.Repo,
    schema: Videdal.Student,
    policy: Hawk.Reader.ResourceTest.Policy

  filter :parent_id do
    fn {:eq, parent_id} -> dynamic([parent_student: link], link.parent_id == ^parent_id) end
  end

  attach :parent_students, when_filter: [:parent_id], multiplies_roots: true do
    join(query, :inner, [root: student], link in assoc(student, :parent_students), as: :parent_student)
  end
end

defmodule Hawk.Reader.ResourceTest.ScopedReader do
  @moduledoc false

  use Hawk.Reader.Resource,
    repo: Videdal.Repo,
    schema: Videdal.Student,
    policy: Hawk.Reader.ResourceTest.Policy

  filter(:id)
  filter(:school_id)

  def scope(query, _params, _opts) do
    where(query, [root: student], student.active == true)
  end
end

defmodule Hawk.Reader.ResourceTest do
  use Videdal.DatabaseCase, async: true

  import Ecto.Query, only: [from: 2]

  alias Hawk.Authority
  alias Hawk.Reader.ResourceTest.CountReader
  alias Hawk.Reader.ResourceTest.ForcedSchoolReader
  alias Hawk.Reader.ResourceTest.MultiplyingCountReader
  alias Hawk.Reader.ResourceTest.PolicySchoolReader
  alias Hawk.Reader.ResourceTest.PreservingReader
  alias Hawk.Reader.ResourceTest.Reader
  alias Hawk.Reader.ResourceTest.ScopedReader

  test "generates reader metadata functions" do
    assert Reader.filter_keys() ==
             MapSet.new([:id, :school_id, :active, :activity, :student_id, :school_name])

    assert Map.has_key?(Reader.filter_handlers(), :student_id)
    assert Map.has_key?(Reader.filter_handlers(), :activity)
    assert Reader.filter_value_types() == %{activity: :object}

    assert [
             %{
               name: :school,
               when_filter: when_filter,
               when_sort: when_sort,
               preserves_roots: false,
               multiplies_roots: false
             }
           ] = Reader.join_plan()

    assert when_filter == MapSet.new([:school_name])
    assert when_sort == MapSet.new([:school_name])
    assert Reader.preload_keys() == MapSet.new([:school])

    assert Reader.preload_readers() == %{}

    assert Reader.read_filter(Authority.system()) == :all
  end

  test "object-valued custom filters receive normalized objects" do
    school = insert(:school)
    active_student = insert(:student, school_id: school.id, active: true)
    insert(:student, school_id: school.id, active: false)

    assert [found] =
             Reader.all(
               authority: Authority.system(),
               filter: %{activity: %{"active" => true}}
             )

    assert found.id == active_student.id
  end

  test "rejects invalid object-valued custom filter declarations" do
    cases = [
      {"filter :structured, value: :array do\n  fn value -> value end\nend", ~r/value must be :object/},
      {"filter :structured, value: :object, unknown: true do\n  fn value -> value end\nend",
       ~r/unknown custom filter options/},
      {"filter :structured, value: :object, value: :object do\n  fn value -> value end\nend",
       ~r/duplicate custom filter options/},
      {"filter(:structured, value: :object)", ~r/requires a custom handler block/},
      {"filter :structured, type: :coordinates, max_radius_meters: 100 do\n  fn value -> value end\nend",
       ~r/unknown custom filter options/}
    ]

    for {declaration, message} <- cases do
      module_suffix = System.unique_integer([:positive])

      assert_raise ArgumentError, message, fn ->
        Code.compile_string("""
        defmodule Hawk.Reader.ResourceTest.InvalidObjectFilter#{module_suffix} do
          use Hawk.Reader.Resource,
            repo: Videdal.Repo,
            schema: Videdal.Student,
            policy: Hawk.Reader.ResourceTest.Policy

          #{declaration}
        end
        """)
      end
    end
  end

  test "generates all/1 through the shared reader runtime" do
    school = insert(:school, id: "00000000-0000-0000-0000-000000000007")
    student = insert(:student, id: "00000000-0000-0000-0000-000000000012", school_id: school.id)

    [result] = Reader.all(authority: Authority.system(), filter: %{student_id: student.id})

    assert result.id == student.id
  end

  test "applies explicit join steps only when triggered by filters" do
    school = insert(:school, id: "00000000-0000-0000-0000-000000000007", name: "Videdal Skole")
    student = insert(:student, school_id: school.id)

    [result] = Reader.all(authority: Authority.system(), filter: %{school_name: "Videdal Skole"})

    assert result.id == student.id
  end

  test "rejects a non-preserving attach when an OR path does not require it" do
    assert_raise ArgumentError, ~r/unsafe reader attach :school/, fn ->
      Reader.all(
        authority: Authority.system(),
        filter: {:or, %{school_name: "Videdal School"}, %{student_id: Ecto.UUID.generate()}}
      )
    end
  end

  test "allows a non-preserving attach when every OR path requires it" do
    school_a = insert(:school, name: "School A")
    school_b = insert(:school, name: "School B")
    student_a = insert(:student, school_id: school_a.id)
    student_b = insert(:student, school_id: school_b.id)

    results =
      Reader.all(
        authority: Authority.system(),
        filter: {:or, %{school_name: "School A"}, %{school_name: "School B"}}
      )

    assert MapSet.new(results, & &1.id) == MapSet.new([student_a.id, student_b.id])
  end

  test "allows a non-preserving attach required by an enclosing AND" do
    school = insert(:school, name: "Videdal School")
    student = insert(:student, school_id: school.id)

    filter =
      {:and, %{school_name: "Videdal School"}, {:or, %{school_name: "Other School"}, %{student_id: student.id}}}

    assert [found] = Reader.all(authority: Authority.system(), filter: filter)
    assert found.id == student.id
  end

  test "allows a non-preserving attach required by a forced filter" do
    school = insert(:school, name: "Videdal School")
    student = insert(:student, school_id: school.id)

    filter = {:or, %{school_name: "Other School"}, %{student_id: student.id}}

    assert [found] = ForcedSchoolReader.all(authority: Authority.system(), filter: filter)
    assert found.id == student.id
  end

  test "allows a non-preserving attach required by a policy filter" do
    school = insert(:school, name: "Videdal School")
    student = insert(:student, school_id: school.id)

    filter = {:or, %{school_name: "Other School"}, %{student_id: student.id}}

    assert [found] = PolicySchoolReader.all(authority: Authority.system(), filter: filter)
    assert found.id == student.id
  end

  test "allows a root-preserving attach when only one OR path requires it" do
    matching_school = insert(:school, name: "Videdal School")
    school_match = insert(:student, school_id: matching_school.id)
    identity_match = insert(:student, school_id: nil)

    filter = {:or, %{school_name: "Videdal School"}, %{student_id: identity_match.id}}
    results = PreservingReader.all(authority: Authority.system(), filter: filter)

    assert MapSet.new(results, & &1.id) == MapSet.new([school_match.id, identity_match.id])
  end

  test "count/1 counts distinct roots across multiplicative joins" do
    school = insert(:school)
    student = insert(:student, school_id: school.id)
    parent = insert(:parent, school_id: school.id)

    for _index <- 1..2 do
      Repo.insert!(%Videdal.ParentStudent{
        id: Ecto.UUID.generate(),
        school_id: school.id,
        student_id: student.id,
        parent_id: parent.id
      })
    end

    assert MultiplyingCountReader.count(authority: Authority.system(), filter: %{parent_id: parent.id}) == 1
  end

  test "count/1 ignores joins triggered only by sort" do
    school = insert(:school)
    student = insert(:student, school_id: school.id)
    parent_one = insert(:parent, school_id: school.id)
    parent_two = insert(:parent, school_id: school.id)

    Repo.insert!(%Videdal.ParentStudent{
      id: Ecto.UUID.generate(),
      school_id: school.id,
      student_id: student.id,
      parent_id: parent_one.id
    })

    Repo.insert!(%Videdal.ParentStudent{
      id: Ecto.UUID.generate(),
      school_id: school.id,
      student_id: student.id,
      parent_id: parent_two.id
    })

    assert CountReader.count(authority: Authority.system(), sort: [asc: :parent_student_id]) == 1
  end

  test "rejects invalid attach multiplicity options" do
    module_suffix = System.unique_integer([:positive])

    assert_raise ArgumentError, ~r/multiplies_roots.*boolean/, fn ->
      Code.compile_string("""
      defmodule Hawk.Reader.ResourceTest.InvalidMultiplicity#{module_suffix} do
        use Hawk.Reader.Resource,
          repo: Videdal.Repo,
          schema: Videdal.Student,
          policy: Hawk.Reader.ResourceTest.Policy

        attach :parents, when_filter: [:parent_id], multiplies_roots: :sometimes do
          query
        end
      end
      """)
    end
  end

  test "rejects invalid attach safety options" do
    module_suffix = System.unique_integer([:positive])

    assert_raise ArgumentError, ~r/preserves_roots.*boolean/, fn ->
      Code.compile_string("""
      defmodule Hawk.Reader.ResourceTest.InvalidAttach#{module_suffix} do
        use Hawk.Reader.Resource,
          repo: Videdal.Repo,
          schema: Videdal.Student,
          policy: Hawk.Reader.ResourceTest.Policy

        attach :school, when_filter: [:school_name], preserves_roots: :yes do
          query
        end
      end
      """)
    end
  end

  test "rejects malformed attach trigger keys" do
    module_suffix = System.unique_integer([:positive])

    assert_raise ArgumentError, ~r/when_filter.*list of atoms/, fn ->
      Code.compile_string("""
      defmodule Hawk.Reader.ResourceTest.InvalidAttachKeys#{module_suffix} do
        use Hawk.Reader.Resource,
          repo: Videdal.Repo,
          schema: Videdal.Student,
          policy: Hawk.Reader.ResourceTest.Policy

        attach :school, when_filter: :school_name do
          query
        end
      end
      """)
    end
  end

  test "applies reader scope to root reads and preload queries" do
    school = insert(:school, id: "00000000-0000-0000-0000-000000000007")
    insert(:student, school_id: school.id, active: true)

    results = ScopedReader.all(authority: Authority.system())
    assert length(results) == 1

    query =
      Videdal.Student
      |> from(as: :root)
      |> ScopedReader.preload_query(Authority.system())

    assert inspect(query) =~ "s0.active == true"
  end

  test "preloads declared associations after fetching rows" do
    school = insert(:school, id: "00000000-0000-0000-0000-000000000007")
    insert(:student, school_id: school.id)

    [result] = Reader.all(authority: Authority.system(), preloads: [:school])

    assert Ecto.assoc_loaded?(result.school)
  end

  test "rejects undeclared preloads" do
    assert_raise ArgumentError, ~r/unknown reader preload :courses/, fn ->
      Reader.all(authority: Authority.system(), preloads: [:courses])
    end
  end

  test "generates one/1" do
    school = insert(:school, id: "00000000-0000-0000-0000-000000000007")
    student = insert(:student, school_id: school.id)

    assert {:ok, found} = Reader.one(authority: Authority.system(), filter: %{student_id: student.id})
    assert found.id == student.id
  end
end
