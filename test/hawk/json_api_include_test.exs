defmodule Videdal.Controllers.InvalidIncludeCoursesController do
  use Hawk.JsonApi.Controller,
    resource: Videdal.Courses,
    model: Videdal.Course
end

defmodule Hawk.JsonApiIncludeTest do
  use ExUnit.Case, async: true

  import Hawk.TestConn, only: [conn: 1, resp: 1]

  alias Videdal.Controllers.InvalidIncludeCoursesController
  alias Videdal.Course
  alias Videdal.Grade

  @course_id Videdal.course_id()
  @grade_id Videdal.grade_id()
  @school_id Videdal.school_id()
  @teacher_id Videdal.teacher_id()

  test "dotted include paths preserve order and merge nested paths" do
    assert Hawk.JsonApi.Request.request_options(%{"include" => "teacher,grades.student,grades.course"}) ==
             [
               preloads: [:teacher, grades: [:student, :course]]
             ]
  end

  test "already-loaded has-many relationships are not exposed unless included through Hawk" do
    course = %Course{
      id: @course_id,
      title: "Math",
      school_id: @school_id,
      teacher_id: @teacher_id,
      grades: [%Grade{id: @grade_id, score: 12}]
    }

    assert Hawk.JsonApi.Document.document(course).data.relationships.grades == %{data: []}

    assert Hawk.JsonApi.Document.document(course, preloads: [:grades]).data.relationships.grades == %{
             data: [%{type: "grades", id: @grade_id}]
           }
  end

  test "documents include full resource objects for requested preloads" do
    course = %Course{
      id: @course_id,
      title: "Math",
      school_id: @school_id,
      teacher_id: @teacher_id,
      grades: [%Grade{id: @grade_id, score: 12, course_id: @course_id}]
    }

    document = Hawk.JsonApi.Document.document(course, preloads: [:grades])

    assert document.included == [
             %{
               type: "grades",
               id: @grade_id,
               attributes: %{score: 12},
               relationships: %{
                 student: %{data: nil},
                 course: %{data: %{type: "courses", id: @course_id}}
               }
             }
           ]
  end

  test "controllers return JSON:API bad request errors for invalid includes" do
    conn =
      InvalidIncludeCoursesController.index(
        conn(%{role: :school_admin, scopes: %{school_id: @school_id}}),
        %{"include" => "grades.secret"}
      )

    assert conn.status == 400

    assert resp(conn) == %{
             errors: [
               %{
                 status: "400",
                 code: "bad_request",
                 title: "Bad request",
                 detail: "unknown include \"secret\""
               }
             ]
           }
  end
end
