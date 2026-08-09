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
  alias Hawk.Reader.ResourceTest.Reader
  alias Hawk.Reader.ResourceTest.ScopedReader

  test "generates reader metadata functions" do
    assert Reader.filter_keys() ==
             MapSet.new([:id, :school_id, :active, :student_id, :school_name])

    assert Map.has_key?(Reader.filter_handlers(), :student_id)
    assert [%{name: :school, when_filter: when_filter, when_sort: when_sort}] = Reader.join_plan()
    assert when_filter == MapSet.new([:school_name])
    assert when_sort == MapSet.new([:school_name])
    assert Reader.preload_keys() == MapSet.new([:school])

    assert Reader.preload_readers() == %{}

    assert Reader.read_filter(Authority.system()) == :all
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
