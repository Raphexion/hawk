defmodule Videdal.Integration.NestedIncludePolicyTest.StudentReader do
  @moduledoc false

  use Hawk.Reader.Resource,
    repo: Videdal.Repo,
    schema: Videdal.Student,
    policy: Videdal.Students.Policy

  filter(:id)
  filter(:school_id)
  filter(:active)

  filter :student_id do
    fn {:eq, student_id} ->
      dynamic([student], student.id == ^student_id)
    end
  end

  attach :parent_student, when_filter: [:parent_id] do
    join(query, :inner, [root: student], parent_student in assoc(student, :parent_students), as: :parent_student)
  end

  filter :parent_id do
    fn {:eq, parent_id} ->
      dynamic([parent_student: parent_student], parent_student.parent_id == ^parent_id)
    end
  end
end

defmodule Videdal.Integration.NestedIncludePolicyTest.GradeReader do
  @moduledoc false

  use Hawk.Reader.Resource,
    repo: Videdal.Repo,
    schema: Videdal.Grade,
    policy: Videdal.Grades.Policy

  filter(:id)
  filter(:school_id)
  filter(:student_id)
  filter(:course_id)

  preload(:student, reader: Videdal.Integration.NestedIncludePolicyTest.StudentReader)

  attach :course, when_filter: [:teacher_id] do
    join(query, :inner, [root: grade], course in assoc(grade, :course), as: :course)
  end

  attach :student, when_filter: [:parent_id] do
    join(query, :inner, [root: grade], student in assoc(grade, :student), as: :student)
  end

  attach :parent_student, when_filter: [:parent_id] do
    join(query, :inner, [student: student], parent_student in assoc(student, :parent_students), as: :parent_student)
  end

  filter :teacher_id do
    fn {:eq, teacher_id} ->
      dynamic([course: course], course.teacher_id == ^teacher_id)
    end
  end

  filter :parent_id do
    fn {:eq, parent_id} ->
      dynamic([parent_student: parent_student], parent_student.parent_id == ^parent_id)
    end
  end
end

defmodule Videdal.Integration.NestedIncludePolicyTest.CourseReader do
  @moduledoc false

  use Hawk.Reader.Resource,
    repo: Videdal.Repo,
    schema: Videdal.Course,
    policy: Videdal.Courses.Policy

  filter(:id)
  filter(:school_id)
  filter(:teacher_id)

  preload(:grades, reader: Videdal.Integration.NestedIncludePolicyTest.GradeReader)
end

defmodule Videdal.Integration.NestedIncludePolicyTest do
  use Videdal.DatabaseCase, async: false

  alias Hawk.Authority
  alias Videdal.{Course, Grade, Parent, ParentStudent, Repo, School, Student, Teacher}
  alias Videdal.Integration.NestedIncludePolicyTest.CourseReader

  setup do
    {:ok, seed_school()}
  end

  test "nested includes are constant-query and constrained by every resource policy", data do
    authority =
      Authority.new(:teacher, data.teacher.id, scopes: %{school_id: data.school.id, teacher_id: data.teacher.id})

    {courses, query_count} =
      count_queries(fn ->
        CourseReader.all(authority: authority, preloads: [grades: [:student]])
      end)

    assert query_count == 3
    assert [%Course{grades: [%Grade{student: %Student{name: "Ada"}}]}] = courses
  end

  test "unauthorized nested resources are filtered in SQL, not post-filtered in memory", data do
    authority = Authority.new(:parent, data.parent.id, scopes: %{school_id: data.school.id})

    {courses, query_count} =
      count_queries(fn ->
        CourseReader.all(authority: authority, preloads: [grades: [:student]])
      end)

    assert query_count == 2
    assert [%Course{grades: []}] = courses
  end

  defp seed_school do
    school = Repo.insert!(%School{name: "Videdal Skole"})
    teacher = Repo.insert!(%Teacher{name: "Ms. Curie", school_id: school.id})
    student = Repo.insert!(%Student{name: "Ada", school_id: school.id})
    parent = Repo.insert!(%Parent{name: "Parent", school_id: school.id})

    Repo.insert!(%ParentStudent{
      school_id: school.id,
      parent_id: parent.id,
      student_id: student.id
    })

    course =
      Repo.insert!(%Course{title: "Math", school_id: school.id, teacher_id: teacher.id})

    Repo.insert!(%Grade{
      score: 12,
      school_id: school.id,
      student_id: student.id,
      course_id: course.id
    })

    %{school: school, teacher: teacher, parent: parent}
  end
end
