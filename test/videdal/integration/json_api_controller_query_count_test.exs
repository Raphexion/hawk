defmodule Videdal.Integration.JsonApiControllerQueryCountTest.CourseReader do
  @moduledoc false

  use Hawk.Reader.Resource,
    repo: Videdal.Repo,
    schema: Videdal.Course,
    policy: Videdal.Integration.JsonApiControllerQueryCountTest.Courses.Policy

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
    repo: Videdal.Repo,
    schema: Videdal.Grade,
    policy: Videdal.Integration.JsonApiControllerQueryCountTest.Courses.Policy

  filter(:id)
  filter(:school_id)
  filter(:course_id)
  filter(:student_id)

  preload(:student, reader: Videdal.Integration.JsonApiControllerQueryCountTest.StudentReader)
end

defmodule Videdal.Integration.JsonApiControllerQueryCountTest.StudentReader do
  @moduledoc false

  use Hawk.Reader.Resource,
    repo: Videdal.Repo,
    schema: Videdal.Student,
    policy: Videdal.Integration.JsonApiControllerQueryCountTest.Courses.Policy

  filter(:id)
  filter(:school_id)
end

defmodule Videdal.Integration.JsonApiControllerQueryCountTest.TeacherReader do
  @moduledoc false

  use Hawk.Reader.Resource,
    repo: Videdal.Repo,
    schema: Videdal.Teacher,
    policy: Videdal.Integration.JsonApiControllerQueryCountTest.Courses.Policy

  filter(:id)
  filter(:school_id)
end

defmodule Videdal.Integration.JsonApiControllerQueryCountTest.Courses.Writer do
  @moduledoc false

  use Hawk.Writer.Resource,
    model: Videdal.Course,
    repo: Videdal.Repo,
    policy: Videdal.Integration.JsonApiControllerQueryCountTest.Courses.Policy

  create do
    cast([:title, :school_id, :teacher_id])
  end

  update do
    cast([:title, :school_id, :teacher_id])
  end

  def delete(%Videdal.Course{} = course, authority) do
    Hawk.MutationContext.delete(course, authority)
    |> Hawk.MutationContext.validate_policy(
      &Videdal.Integration.JsonApiControllerQueryCountTest.Courses.Policy.delete?/1
    )
    |> Hawk.RepositoryBoundary.delete(Videdal.Repo)
  end
end

defmodule Videdal.Integration.JsonApiControllerQueryCountTest.Courses.Policy do
  @moduledoc false

  use Hawk.Policy

  read(:all)
  write(:never)
end

defmodule Videdal.Integration.JsonApiControllerQueryCountTest.Courses do
  @moduledoc false

  use Hawk.Resource,
    model: Videdal.Course,
    reader: Videdal.Integration.JsonApiControllerQueryCountTest.CourseReader,
    json_api: Videdal.Courses.JsonApi,
    live_view: false
end

defmodule Videdal.Integration.JsonApiControllerQueryCountTest.CoursesController do
  @moduledoc false

  use Hawk.JsonApi.Controller,
    resource: Videdal.Integration.JsonApiControllerQueryCountTest.Courses,
    model: Videdal.Course
end

defmodule Videdal.Integration.JsonApiControllerQueryCountTest.ControllerCaseHarness do
  @moduledoc false

  alias Hawk.Authority
  alias Videdal.{Course, Repo, School, Teacher}
  alias Videdal.Integration.JsonApiControllerQueryCountTest.CoursesController

  def __hawk_json_api_controller_case__ do
    %{
      controller: CoursesController,
      resource: Videdal.Integration.JsonApiControllerQueryCountTest.Courses,
      model: Course,
      repo: Repo,
      sample_count: 3,
      create_params: nil,
      update_params: nil
    }
  end

  def __hawk_pre_authorities__, do: %{}

  def __hawk_authorities__(_pre_authorities) do
    %{system: Authority.system()}
  end

  def pre_sample(_pre_authorities, _authorities) do
    school = Repo.insert!(%School{name: "Videdal Skole"})
    teacher = Repo.insert!(%Teacher{name: "Ms. Curie", school_id: school.id})
    %{school: school, teacher: teacher}
  end

  def sample(_pre_authorities, _authorities, known, index) do
    %Course{
      id: Ecto.UUID.generate(),
      title: "Course #{index}",
      school_id: known.school.id,
      teacher_id: known.teacher.id
    }
  end
end

defmodule Videdal.Integration.JsonApiControllerQueryCountTest do
  use Videdal.DatabaseCase, async: false

  import Hawk.TestConn, only: [conn: 1, resp: 1]

  alias Hawk.Authority
  alias Videdal.{Course, Grade, Repo, School, Student, Teacher}
  alias Videdal.Integration.JsonApiControllerQueryCountTest.CoursesController

  @moduletag :database

  setup do
    :ok
  end

  test "index nested includes stay constant-query as root rows grow" do
    seed_courses_with_grades(1)

    {_conn, one_course_query_count} =
      count_queries(fn ->
        CoursesController.index(conn(Authority.system()), %{"include" => "grades.student"})
      end)

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

  test "controller case helper asserts bounded index query growth" do
    results =
      Hawk.JsonApiControllerCase.assert_index_query_growth(
        Videdal.Integration.JsonApiControllerQueryCountTest.ControllerCaseHarness,
        include: "teacher",
        parent_counts: [1, 5],
        max_extra_queries: 0,
        authority: :system
      )

    assert [
             %{parent_count: 1, query_count: one_query_count},
             %{parent_count: 5, query_count: five_query_count}
           ] = results

    assert one_query_count == five_query_count
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

  test "related endpoint applies sparse fieldsets to related resources" do
    %{course: course} = seed_courses_with_grades(4)

    {conn, _query_count} =
      count_queries(fn ->
        CoursesController.related(conn(Authority.system()), %{
          "id" => course.id,
          "relationship" => "teacher",
          "fields" => %{"teachers" => "name"}
        })
      end)

    assert conn.status == 200
    assert resp(conn).data.type == "teachers"
    assert resp(conn).data.attributes == %{name: "Ms. Curie"}
    assert resp(conn).data.relationships == %{}
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
    Repo.delete_all(Grade)
    Repo.delete_all(Course)
    Repo.delete_all(Student)

    school = Repo.insert!(%School{name: "Videdal Skole"})
    teacher = Repo.insert!(%Teacher{name: "Ms. Curie", school_id: school.id})

    courses =
      Enum.map(1..count, fn index ->
        student = Repo.insert!(%Student{name: "Student #{index}", school_id: school.id})

        course =
          Repo.insert!(%Course{
            title: "Course #{index}",
            school_id: school.id,
            teacher_id: teacher.id
          })

        Repo.insert!(%Grade{
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
