defmodule Videdal.Integration.JsonApiControllerQueryCountTest.CourseReader do
  @moduledoc false

  use Hawk.Reader.Resource,
    repo: Videdal.SandboxRepo,
    schema: Videdal.Course,
    policy: Videdal.Integration.JsonApiControllerQueryCountTest.AllowAllPolicy

  filter(:id)
  filter(:school_id)
  filter(:teacher_id)

  sort(:id)
  sort(:title)

  preload(:teacher, reader: Videdal.Integration.JsonApiControllerQueryCountTest.TeacherReader)
  preload(:grades, reader: Videdal.Integration.JsonApiControllerQueryCountTest.GradeReader)
end

defmodule Videdal.Integration.JsonApiControllerQueryCountTest.GradeReader do
  @moduledoc false

  use Hawk.Reader.Resource,
    repo: Videdal.SandboxRepo,
    schema: Videdal.Grade,
    policy: Videdal.Integration.JsonApiControllerQueryCountTest.AllowAllPolicy

  filter(:id)
  filter(:school_id)
  filter(:course_id)
  filter(:student_id)

  preload(:student, reader: Videdal.Integration.JsonApiControllerQueryCountTest.StudentReader)
end

defmodule Videdal.Integration.JsonApiControllerQueryCountTest.StudentReader do
  @moduledoc false

  use Hawk.Reader.Resource,
    repo: Videdal.SandboxRepo,
    schema: Videdal.Student,
    policy: Videdal.Integration.JsonApiControllerQueryCountTest.AllowAllPolicy

  filter(:id)
  filter(:school_id)
end

defmodule Videdal.Integration.JsonApiControllerQueryCountTest.TeacherReader do
  @moduledoc false

  use Hawk.Reader.Resource,
    repo: Videdal.SandboxRepo,
    schema: Videdal.Teacher,
    policy: Videdal.Integration.JsonApiControllerQueryCountTest.AllowAllPolicy

  filter(:id)
  filter(:school_id)
end

defmodule Videdal.Integration.JsonApiControllerQueryCountTest.AllowAllPolicy do
  @moduledoc false

  def read_filter(_authority), do: :all
end

defmodule Videdal.Integration.JsonApiControllerQueryCountTest.Courses do
  @moduledoc false

  alias Videdal.Integration.JsonApiControllerQueryCountTest.CourseReader

  def one(opts), do: CourseReader.one(opts)
  def all(opts), do: CourseReader.all(opts)
end

defmodule Videdal.Integration.JsonApiControllerQueryCountTest.CoursesController do
  @moduledoc false

  use Hawk.JsonApi.Controller,
    resource: Videdal.Integration.JsonApiControllerQueryCountTest.Courses,
    model: Videdal.Course
end

defmodule Videdal.Integration.JsonApiControllerQueryCountTest do
  use Videdal.DatabaseCase, async: false

  import Hawk.TestConn, only: [conn: 1, resp: 1]

  alias Hawk.Authority
  alias Videdal.{Course, Grade, SandboxRepo, School, Student, Teacher}
  alias Videdal.Integration.JsonApiControllerQueryCountTest.CoursesController

  @moduletag :database

  setup do
    Videdal.DatabaseCase.reset_schema!()
    :ok
  end

  test "index nested includes stay constant-query as root rows grow" do
    seed_courses_with_grades(1)

    {_conn, one_course_query_count} =
      count_queries(fn ->
        CoursesController.index(conn(Authority.system()), %{"include" => "grades.student"})
      end)

    Videdal.DatabaseCase.reset_schema!()
    seed_courses_with_grades(5)

    {conn, many_course_query_count} =
      count_queries(fn ->
        CoursesController.index(conn(Authority.system()), %{"include" => "grades.student"})
      end)

    assert conn.status == 200
    assert length(resp(conn).data) == 5
    assert one_course_query_count == 3
    assert many_course_query_count == one_course_query_count
  end

  test "related to-one endpoint uses one root query and one batched preload query" do
    %{course: course} = seed_courses_with_grades(4)

    {conn, query_count} =
      count_queries(fn ->
        CoursesController.related(conn(Authority.system()), %{"id" => course.id, "relationship" => "teacher"})
      end)

    assert conn.status == 200
    assert resp(conn).data.type == "teachers"
    assert query_count == 2
  end

  test "related to-many endpoint uses one root query and one batched preload query" do
    %{course: course} = seed_courses_with_grades(4)

    {conn, query_count} =
      count_queries(fn ->
        CoursesController.related(conn(Authority.system()), %{"id" => course.id, "relationship" => "grades"})
      end)

    assert conn.status == 200
    assert length(resp(conn).data) == 1
    assert query_count == 2
  end

  test "to-many relationship linkage endpoint preloads related identifiers" do
    %{course: course} = seed_courses_with_grades(4)

    {conn, query_count} =
      count_queries(fn ->
        CoursesController.relationship(conn(Authority.system()), %{"id" => course.id, "relationship" => "grades"})
      end)

    assert conn.status == 200
    assert [%{type: "grades"}] = resp(conn).data
    assert query_count == 2
  end

  test "to-one relationship linkage endpoint returns identifiers from the foreign key without a preload" do
    %{course: course} = seed_courses_with_grades(4)

    {conn, query_count} =
      count_queries(fn ->
        CoursesController.relationship(conn(Authority.system()), %{"id" => course.id, "relationship" => "teacher"})
      end)

    assert conn.status == 200
    assert resp(conn).data == %{type: "teachers", id: course.teacher_id}
    assert query_count == 1
  end

  defp seed_courses_with_grades(count) do
    school = SandboxRepo.insert!(%School{name: "Videdal Skole"})
    teacher = SandboxRepo.insert!(%Teacher{name: "Ms. Curie", school_id: school.id})

    courses =
      Enum.map(1..count, fn index ->
        student = SandboxRepo.insert!(%Student{name: "Student #{index}", school_id: school.id})

        course =
          SandboxRepo.insert!(%Course{
            title: "Course #{index}",
            school_id: school.id,
            teacher_id: teacher.id
          })

        SandboxRepo.insert!(%Grade{
          score: 12,
          school_id: school.id,
          student_id: student.id,
          course_id: course.id
        })

        course
      end)

    %{school: school, teacher: teacher, course: hd(courses), courses: courses}
  end

end
