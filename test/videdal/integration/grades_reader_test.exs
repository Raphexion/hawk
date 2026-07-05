defmodule Videdal.Integration.GradesReaderTest.Reader do
  @moduledoc false

  use Hawk.Reader.Resource,
    repo: Videdal.SandboxRepo,
    schema: Videdal.Grade,
    policy: Videdal.Grades.Policy

  filter(:id)
  filter(:school_id)
  filter(:student_id)
  filter(:course_id)
  filter(:score)

  preload(:student, policy: Videdal.Students.Policy)
  preload(:course, policy: Videdal.Courses.Policy)

  attach :student, when_filter: [:student_name, :parent_id] do
    join(query, :inner, [root: grade], student in assoc(grade, :student), as: :student)
  end

  attach :parent_student, when_filter: [:parent_id] do
    join(query, :inner, [student: student], parent_student in assoc(student, :parent_students),
      as: :parent_student
    )
  end

  attach :course, when_filter: [:course_title, :teacher_id] do
    join(query, :inner, [root: grade], course in assoc(grade, :course), as: :course)
  end

  filter :student_name do
    fn {:eq, student_name} -> dynamic([student: student], student.name == ^student_name) end
  end

  filter :parent_id do
    fn {:eq, parent_id} ->
      dynamic([parent_student: parent_student], parent_student.parent_id == ^parent_id)
    end
  end

  filter :course_title do
    fn {:eq, course_title} -> dynamic([course: course], course.title == ^course_title) end
  end

  filter :teacher_id do
    fn {:eq, teacher_id} -> dynamic([course: course], course.teacher_id == ^teacher_id) end
  end
end

defmodule Videdal.Integration.GradesReaderTest do
  use Videdal.DatabaseCase, async: false

  alias Hawk.Authority
  alias Videdal.{Course, Grade, Parent, ParentStudent, SandboxRepo, School, Student, Teacher}
  alias Videdal.Integration.GradesReaderTest.Reader

  setup do
    Videdal.DatabaseCase.reset_schema!()
    {:ok, seed_school()}
  end

  test "teachers query all grades for their courses with batched preloads", data do
    authority =
      Authority.new(:teacher, data.teacher.id,
        scopes: %{school_id: data.school.id, teacher_id: data.teacher.id}
      )

    {grades, query_count} =
      count_queries(fn ->
        Reader.all(authority: authority, preloads: [:student, :course])
      end)

    assert Enum.map(grades, & &1.score) == [12, 10]
    assert Enum.map(grades, & &1.student.name) == ["Ada", "Grace"]
    assert Enum.map(grades, & &1.course.title) == ["Math", "Math"]
    assert query_count == 3
  end

  test "students can only query their own grades", data do
    authority =
      Authority.new(:student, data.ada.id,
        scopes: %{school_id: data.school.id, student_id: data.ada.id}
      )

    assert [%Grade{score: 12}, %Grade{score: 7}] = Reader.all(authority: authority)
    assert Reader.all(authority: authority, filter: %{student_id: data.grace.id}) == []
  end

  test "parents query grades through linked students only", data do
    authority =
      Authority.new(:parent, data.parent.id,
        scopes: %{school_id: data.school.id, parent_id: data.parent.id}
      )

    {grades, query_count} =
      count_queries(fn ->
        Reader.all(authority: authority, preloads: [:student, :course])
      end)

    assert [
             %Grade{score: 12, student: %Student{name: "Ada"}, course: %Course{title: "Math"}},
             %Grade{score: 7, student: %Student{name: "Ada"}, course: %Course{title: "Physics"}}
           ] = grades

    assert query_count == 3
  end

  defp seed_school do
    school = SandboxRepo.insert!(%School{name: "Videdal Skole"})
    teacher = SandboxRepo.insert!(%Teacher{name: "Ms. Curie", school_id: school.id})
    other_teacher = SandboxRepo.insert!(%Teacher{name: "Mr. Feynman", school_id: school.id})

    ada = SandboxRepo.insert!(%Student{name: "Ada", school_id: school.id})
    grace = SandboxRepo.insert!(%Student{name: "Grace", school_id: school.id})

    math =
      SandboxRepo.insert!(%Course{title: "Math", school_id: school.id, teacher_id: teacher.id})

    physics =
      SandboxRepo.insert!(%Course{
        title: "Physics",
        school_id: school.id,
        teacher_id: other_teacher.id
      })

    parent = SandboxRepo.insert!(%Parent{name: "Ada Parent", school_id: school.id})

    SandboxRepo.insert!(%ParentStudent{
      school_id: school.id,
      parent_id: parent.id,
      student_id: ada.id
    })

    SandboxRepo.insert!(%Grade{
      score: 12,
      school_id: school.id,
      student_id: ada.id,
      course_id: math.id
    })

    SandboxRepo.insert!(%Grade{
      score: 10,
      school_id: school.id,
      student_id: grace.id,
      course_id: math.id
    })

    SandboxRepo.insert!(%Grade{
      score: 7,
      school_id: school.id,
      student_id: ada.id,
      course_id: physics.id
    })

    %{
      school: school,
      teacher: teacher,
      ada: ada,
      grace: grace,
      parent: parent
    }
  end
end
