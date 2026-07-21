defmodule Videdal.Controllers.AuthenticatedCoursesController do
  use Hawk.JsonApi.Controller,
    resource: Videdal.Courses,
    model: Videdal.Course
end

defmodule Videdal.Controllers.PublicCoursesController do
  use Hawk.JsonApi.Controller,
    resource: Videdal.Courses,
    model: Videdal.Course,
    public: true
end

defmodule Hawk.PublicAuthorityTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Videdal.Controllers.AuthenticatedCoursesController
  alias Videdal.Controllers.PublicCoursesController
  alias Videdal.Course
  alias Videdal.Courses.Policy

  @school_id Videdal.school_id()
  @teacher_id Videdal.teacher_id()

  test "public authority is readonly and not system privileged" do
    authority = Authority.public()

    assert authority.role == :public
    assert authority.identity == :public
    assert Authority.public?(authority)
    assert Authority.readonly?(authority)
    refute Authority.system?(authority)
  end

  test "policy DSL can expose read access to public callers" do
    assert Policy.read_filter(Authority.public()) == :all
  end

  test "public controller actions can read without an assigned authority" do
    courses = [%Course{id: 3, title: "Math", school_id: 7, teacher_id: 12}]
    Process.put({Videdal.Repo, :all_results}, courses)

    conn = PublicCoursesController.index(conn(), %{})

    assert conn.status == 200
    assert conn.resp_body.data == [Hawk.JsonApi.document(hd(courses)).data]
  end

  test "deeper includes do not bypass nested policies for public endpoints" do
    courses = [%Course{id: 3, title: "Math", school_id: 7, teacher_id: 12}]
    Process.put({Videdal.Repo, :all_results}, courses)

    conn = PublicCoursesController.index(conn(), %{"include" => "grades.student"})

    assert conn.status == 200

    assert_received {:videdal_repo, :preload, ^courses, [grades: {grade_query, [student: student_query]}]}

    assert inspect(grade_query) =~ "where: false"
    assert inspect(student_query) =~ "where: false"
  end

  test "deeper includes apply each nested resource policy for authenticated endpoints too" do
    courses = [%Course{id: 3, title: "Math", school_id: 7, teacher_id: 12}]
    Process.put({Videdal.Repo, :all_results}, courses)

    conn =
      AuthenticatedCoursesController.index(
        conn(%{role: :teacher, scopes: %{school_id: 7, teacher_id: 12}}),
        %{"include" => "grades.student"}
      )

    assert conn.status == 200

    assert_received {:videdal_repo, :preload, ^courses, [grades: {grade_query, [student: student_query]}]}

    assert inspect(grade_query) =~ "c1.teacher_id == ^12"
    assert inspect(student_query) =~ "s0.school_id == ^7"
  end

  test "deeper includes are constrained when authenticated authority cannot read nested resources" do
    courses = [%Course{id: 3, title: "Math", school_id: 7, teacher_id: 12}]
    Process.put({Videdal.Repo, :all_results}, courses)

    conn =
      AuthenticatedCoursesController.index(
        conn(%{role: :parent, scopes: %{school_id: 7}}),
        %{"include" => "grades.student"}
      )

    assert conn.status == 200
    assert_received {:videdal_repo, :all, course_query}

    assert_received {:videdal_repo, :preload, ^courses, [grades: {grade_query, [student: student_query]}]}

    assert inspect(course_query) =~ "c0.school_id == ^7"
    assert inspect(grade_query) =~ "where: false"
    assert inspect(student_query) =~ "where: false"
  end

  test "public controller actions still reject writes through readonly authority" do
    conn =
      PublicCoursesController.create(conn(), %{
        "data" => %{
          "type" => "courses",
          "attributes" => %{"title" => "Math"},
          "relationships" => %{
            "school" => %{"data" => %{"type" => "schools", "id" => @school_id}},
            "teacher" => %{"data" => %{"type" => "teachers", "id" => @teacher_id}}
          }
        }
      })

    assert conn.status == 403
    assert [%{status: "403", code: "not_authorized"}] = conn.resp_body.errors
  end

  defp conn, do: %{assigns: %{}, status: nil, resp_body: nil}

  defp conn(%{role: role, scopes: scopes}) do
    %{assigns: %{authority: Authority.new(role, 1, scopes: scopes)}, status: nil, resp_body: nil}
  end
end
