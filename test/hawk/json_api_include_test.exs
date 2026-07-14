defmodule Videdal.Controllers.InvalidIncludeCoursesController do
  use Hawk.JsonApi.Controller,
    resource: Videdal.Courses,
    model: Videdal.Course
end

defmodule Hawk.JsonApiIncludeTest do
  use ExUnit.Case, async: true

  alias Videdal.Controllers.InvalidIncludeCoursesController
  alias Videdal.Course
  alias Videdal.Grade

  test "dotted include paths preserve order and merge nested paths" do
    assert Hawk.JsonApi.request_options(%{"include" => "teacher,grades.student,grades.course"}) ==
             [
               preloads: [:teacher, grades: [:student, :course]]
             ]
  end

  test "already-loaded has-many relationships are not exposed unless included through Hawk" do
    course = %Course{
      id: 3,
      title: "Math",
      school_id: 7,
      teacher_id: 12,
      grades: [%Grade{id: 1, score: 12}]
    }

    assert Hawk.JsonApi.document(course).data.relationships.grades == %{data: []}

    assert Hawk.JsonApi.document(course, preloads: [:grades]).data.relationships.grades == %{
             data: [%{type: "grades", id: "1"}]
           }
  end

  test "documents include full resource objects for requested preloads" do
    course = %Course{
      id: 3,
      title: "Math",
      school_id: 7,
      teacher_id: 12,
      grades: [%Grade{id: 1, score: 12, course_id: 3}]
    }

    document = Hawk.JsonApi.document(course, preloads: [:grades])

    assert document.included == [
             %{
               type: "grades",
               id: "1",
               attributes: %{score: 12},
               relationships: %{
                 student: %{data: nil},
                 course: %{data: %{type: "courses", id: "3"}}
               }
             }
           ]
  end

  test "controllers return JSON:API bad request errors for invalid includes" do
    conn =
      InvalidIncludeCoursesController.index(
        conn(%{role: :school_admin, scopes: %{school_id: 7}}),
        %{"include" => "grades.secret"}
      )

    assert conn.status == 400

    assert conn.resp_body == %{
             errors: [
               %{
                 status: "400",
                 code: "bad_request",
                 title: "Bad request",
                 detail: "unknown reader preload :secret"
               }
             ]
           }
  end

  defp conn(%{role: role, scopes: scopes}) do
    %{
      assigns: %{authority: Hawk.Authority.new(role, 1, scopes: scopes)},
      status: nil,
      resp_body: nil
    }
  end
end
