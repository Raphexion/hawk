defmodule Videdal.Controllers.ErrorBoundaryCoursesController do
  use Hawk.JsonApi.Controller,
    resource: Videdal.Courses,
    model: Videdal.Course
end

defmodule Hawk.JsonApiControllerErrorBoundaryTest do
  use ExUnit.Case, async: true

  @school_admin_id Videdal.school_admin_id()
  @school_id Videdal.school_id()
  @student_id Videdal.student_id()
  @teacher_id Videdal.teacher_id()

  test "invalid sort returns a JSON:API 400 error" do
    conn =
      Videdal.Controllers.ErrorBoundaryCoursesController.index(conn(), %{
        "sort" => "teacher_id"
      })

    assert conn.status == 400
    assert [error] = conn.resp_body.errors
    assert error.status == "400"
    assert error.code == "bad_request"
    assert error.detail == "unsupported sort column :teacher_id"
  end

  test "invalid pagination returns a JSON:API 400 error" do
    conn =
      Videdal.Controllers.ErrorBoundaryCoursesController.index(conn(), %{
        "page" => %{"size" => "many"}
      })

    assert conn.status == 400
    assert [error] = conn.resp_body.errors
    assert error.status == "400"
    assert error.code == "bad_request"
  end

  test "validation, authorization, and missing records keep their explicit statuses" do
    Process.put({Videdal.Repo, :all_results}, [])

    missing = Videdal.Controllers.ErrorBoundaryCoursesController.show(conn(), %{"id" => "404"})
    assert missing.status == 404

    unauthorized =
      Videdal.Controllers.ErrorBoundaryCoursesController.create(
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
      Videdal.Controllers.ErrorBoundaryCoursesController.create(conn(), %{
        "data" => %{"type" => "courses", "attributes" => %{"title" => "Math"}}
      })

    assert invalid.status == 422
  end

  defp conn(authority_opts \\ %{role: :school_admin, scopes: %{school_id: @school_id}}) do
    %{assigns: %{authority: authority(authority_opts)}, status: nil, resp_body: nil}
  end

  defp authority(%{role: role, scopes: scopes}),
    do: Hawk.Authority.new(role, @school_admin_id, scopes: scopes)
end
