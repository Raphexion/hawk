defmodule Videdal.Integration.StudentParentsPreloadTest.StudentsReader do
  @moduledoc false

  use Hawk.Reader.Resource,
    repo: Videdal.Repo,
    schema: Videdal.Student,
    policy: Videdal.Integration.StudentParentsPreloadTest.AllowAllPolicy

  filter(:id)
  filter(:school_id)

  preload(:parents)
end

defmodule Videdal.Integration.StudentParentsPreloadTest.ParentsReader do
  @moduledoc false

  use Hawk.Reader.Resource,
    repo: Videdal.Repo,
    schema: Videdal.Parent,
    policy: Videdal.Integration.StudentParentsPreloadTest.AllowAllPolicy

  filter(:id)
  filter(:school_id)

  preload(:students)
end

defmodule Videdal.Integration.StudentParentsPreloadTest.AllowAllPolicy do
  @moduledoc false

  def read_filter(_authority), do: :all
end

defmodule Videdal.Integration.StudentParentsPreloadTest do
  use Videdal.DatabaseCase, async: false

  alias Hawk.Authority
  alias Videdal.Integration.StudentParentsPreloadTest.{ParentsReader, StudentsReader}
  alias Videdal.{Parent, ParentStudent, Repo, School, Student}

  @moduletag :database

  setup do
    :ok
  end

  test "students expose parents through the many-to-many association without exposing join rows" do
    school = Repo.insert!(%School{name: "Videdal Skole"})
    alma = Repo.insert!(%Student{name: "Alma", school_id: school.id})
    anna = Repo.insert!(%Parent{name: "Anna", school_id: school.id})
    marcus = Repo.insert!(%Parent{name: "Marcus", school_id: school.id})

    Repo.insert!(%ParentStudent{
      school_id: school.id,
      student_id: alma.id,
      parent_id: anna.id
    })

    Repo.insert!(%ParentStudent{
      school_id: school.id,
      student_id: alma.id,
      parent_id: marcus.id
    })

    assert [student] = StudentsReader.all(authority: Authority.system(), preloads: [:parents])
    assert Enum.map(student.parents, & &1.name) |> Enum.sort() == ["Anna", "Marcus"]

    document = Hawk.JsonApi.Document.document(student, preloads: [:parents])

    assert Enum.sort_by(document.data.relationships.parents.data, & &1.id) ==
             Enum.sort_by(
               [
                 %{type: "parents", id: anna.id},
                 %{type: "parents", id: marcus.id}
               ],
               & &1.id
             )

    refute Map.has_key?(document.data.relationships, :parent_students)
  end

  test "parents expose students through the inverse many-to-many association" do
    school = Repo.insert!(%School{name: "Videdal Skole"})
    anna = Repo.insert!(%Parent{name: "Anna", school_id: school.id})

    students =
      Enum.map(["Alma", "Birk", "Clara"], fn name ->
        student = Repo.insert!(%Student{name: name, school_id: school.id})

        Repo.insert!(%ParentStudent{
          school_id: school.id,
          student_id: student.id,
          parent_id: anna.id
        })

        student
      end)

    assert [parent] = ParentsReader.all(authority: Authority.system(), preloads: [:students])
    assert Enum.map(parent.students, & &1.name) |> Enum.sort() == ["Alma", "Birk", "Clara"]

    document = Hawk.JsonApi.Document.document(parent, preloads: [:students])

    assert Enum.sort_by(document.data.relationships.students.data, & &1.id) ==
             students
             |> Enum.map(&%{type: "students", id: &1.id})
             |> Enum.sort_by(& &1.id)

    refute Map.has_key?(document.data.relationships, :parent_students)
  end
end
