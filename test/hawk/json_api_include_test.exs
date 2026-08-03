defmodule Videdal.Controllers.InvalidIncludeCoursesController do
  use Hawk.JsonApi.Controller,
    resource: Videdal.Courses
end

defmodule Hawk.JsonApiIncludeTest do
  use ExUnit.Case, async: true

  import Hawk.TestConn, only: [conn: 1, resp: 1]

  alias Videdal.Controllers.InvalidIncludeCoursesController
  alias Videdal.Course
  alias Videdal.Grade
  alias Videdal.Teacher

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

    refute Map.has_key?(Hawk.JsonApi.Document.document(course).data.relationships, :grades)

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

  test "documents apply sparse fieldsets to included resource objects" do
    course = %Course{
      id: @course_id,
      title: "Math",
      school_id: @school_id,
      teacher_id: @teacher_id,
      teacher: %Teacher{id: @teacher_id, name: "Ms. Curie", school_id: @school_id}
    }

    document =
      Hawk.JsonApi.Document.document(course,
        preloads: [:teacher],
        fields: %{"courses" => MapSet.new(["title", "teacher"]), "teachers" => MapSet.new(["name"])}
      )

    assert document.data.attributes == %{title: "Math"}
    assert document.data.relationships == %{teacher: %{data: %{type: "teachers", id: @teacher_id}}}

    assert document.included == [
             %{
               type: "teachers",
               id: @teacher_id,
               attributes: %{name: "Ms. Curie"},
               relationships: %{}
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
