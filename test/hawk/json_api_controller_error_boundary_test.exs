defmodule Videdal.Controllers.ErrorBoundaryCoursesController do
  use Hawk.JsonApi.Controller,
    resource: Videdal.Courses
end

defmodule Hawk.JsonApiControllerErrorBoundaryTest do
  use ExUnit.Case, async: true

  import Hawk.TestConn, only: [conn: 1, resp: 1]

  alias Hawk.Authority
  alias Videdal.Controllers.ErrorBoundaryCoursesController

  @school_admin_id Videdal.school_admin_id()
  @school_id Videdal.school_id()
  @student_id Videdal.student_id()
  @teacher_id Videdal.teacher_id()
  @school_admin Authority.new(:school_admin, @school_admin_id, scopes: %{school_id: @school_id})

  test "invalid sort returns a JSON:API 400 error" do
    conn =
      ErrorBoundaryCoursesController.index(conn(@school_admin), %{
        "sort" => "teacher_id"
      })

    assert conn.status == 400
    assert [error] = resp(conn).errors
    assert error.status == "400"
    assert error.code == "bad_request"
    assert error.detail == "unsupported sort column :teacher_id"
  end

  test "invalid pagination returns a JSON:API 400 error" do
    conn =
      ErrorBoundaryCoursesController.index(conn(@school_admin), %{
        "page" => %{"size" => "many"}
      })

    assert conn.status == 400
    assert [error] = resp(conn).errors
    assert error.status == "400"
    assert error.code == "bad_request"
  end

  test "validation, authorization, and missing records keep their explicit statuses" do
    Process.put({Videdal.Repo, :all_results}, [])

    missing = ErrorBoundaryCoursesController.show(conn(@school_admin), %{"id" => Videdal.other_course_id()})
    assert missing.status == 404

    unauthorized =
      ErrorBoundaryCoursesController.create(
        conn(%{role: :student, scopes: %{school_id: @school_id, student_id: @student_id}}),
        %{
          "data" => %{
            "type" => "courses",
            "attributes" => %{"title" => "Math"},
            "relationships" => %{
              "school" => %{"data" => %{"type" => "schools", "id" => @school_id}},
              "teacher" => %{"data" => %{"type" => "teachers", "id" => @teacher_id}}
            }
          }
        }
      )

    assert unauthorized.status == 403

    invalid =
      ErrorBoundaryCoursesController.create(conn(@school_admin), %{
        "data" => %{"type" => "courses", "attributes" => %{"title" => "Math"}}
      })

    assert invalid.status == 422
  end
end
