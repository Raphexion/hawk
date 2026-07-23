defmodule Hawk.ControllerBoundaryPathsTest.CoursesController do
  use Hawk.JsonApi.Controller,
    resource: Videdal.Courses,
    model: Videdal.Course
end

defmodule Hawk.ControllerBoundaryPathsTest.ErrorResource do
  def create(_attrs, _authority), do: {:error, "database unavailable"}
end

defmodule Hawk.ControllerBoundaryPathsTest.OkDeleteResource do
  def one(_opts) do
    {:ok,
     %Videdal.Course{
       id: Videdal.course_id(),
       title: "Math",
       school_id: Videdal.school_id(),
       teacher_id: Videdal.teacher_id()
     }}
  end

  def delete(_course, _authority), do: :ok
end

defmodule Hawk.ControllerBoundaryPathsTest.MissingHandlerResource do
  def one(_opts) do
    {:ok,
     %Videdal.Course{
       id: Videdal.course_id(),
       title: "Math",
       school_id: Videdal.school_id(),
       teacher_id: Videdal.teacher_id()
     }}
  end
end

defmodule Hawk.ControllerBoundaryPathsTest.MissingHandlerResource.Actions do
  use Hawk.Actions

  action("open-registration",
    handler: :missing_handler,
    params: [seat_count: [type: :integer]]
  )
end

defmodule Hawk.ControllerBoundaryPathsTest.ErrorController do
  use Hawk.JsonApi.Controller,
    resource: Hawk.ControllerBoundaryPathsTest.ErrorResource,
    model: Videdal.Course
end

defmodule Hawk.ControllerBoundaryPathsTest.OkDeleteController do
  use Hawk.JsonApi.Controller,
    resource: Hawk.ControllerBoundaryPathsTest.OkDeleteResource,
    model: Videdal.Course
end

defmodule Hawk.ControllerBoundaryPathsTest.PublicCoursesController do
  use Hawk.JsonApi.Controller,
    resource: Videdal.Courses,
    model: Videdal.Course,
    public: true
end

defmodule Hawk.ControllerBoundaryPathsTest.MissingHandlerController do
  use Hawk.JsonApi.Controller,
    resource: Hawk.ControllerBoundaryPathsTest.MissingHandlerResource,
    model: Videdal.Course
end

defmodule Hawk.ControllerBoundaryPathsTest do
  use ExUnit.Case, async: true

  alias Hawk.ControllerBoundaryPathsTest.CoursesController
  alias Hawk.ControllerBoundaryPathsTest.ErrorController
  alias Hawk.ControllerBoundaryPathsTest.MissingHandlerController
  alias Hawk.ControllerBoundaryPathsTest.OkDeleteController
  alias Hawk.ControllerBoundaryPathsTest.PublicCoursesController
  alias Videdal.Course

  @course_id Videdal.course_id()
  @school_id Videdal.school_id()
  @teacher_id Videdal.teacher_id()

  test "delete returns 204 No Content with an empty body" do
    conn = OkDeleteController.delete(conn(), %{"id" => @course_id})

    assert conn.status == 204
    assert conn.resp_body == nil
  end

  test "delete returns not found through the controller boundary" do
    Process.put({Videdal.Repo, :all_results}, [])

    conn = CoursesController.delete(conn(), %{"id" => Videdal.other_course_id()})

    assert conn.status == 404
    assert [%{status: "404", code: "not_found"}] = conn.resp_body.errors
  end

  test "resource errors become JSON:API 500 errors" do
    conn =
      ErrorController.create(conn(), %{
        "data" => %{"type" => "courses", "attributes" => %{}}
      })

    assert conn.status == 500

    assert conn.resp_body == %{
             errors: [
               %{
                 status: "500",
                 code: "error",
                 title: "Error",
                 detail: "database unavailable"
               }
             ]
           }
  end

  test "public controllers can route actions and still enforce write authorization" do
    course = %Course{
      id: @course_id,
      title: "Math",
      school_id: @school_id,
      teacher_id: @teacher_id
    }

    Process.put({Videdal.Repo, :all_results}, [course])

    conn =
      PublicCoursesController.action(
        %{assigns: %{}, status: nil, resp_body: nil},
        %{
          "id" => @course_id,
          "action" => "open-registration",
          "meta" => %{"seat_count" => 1, "waitlist_count" => 0}
        }
      )

    assert conn.status == 403
    assert [%{status: "403", code: "not_authorized"}] = conn.resp_body.errors
  end

  test "actions with declared but missing handlers return action_not_found through the controller boundary" do
    conn =
      MissingHandlerController.action(conn(), %{
        "id" => @course_id,
        "action" => "open-registration",
        "meta" => %{"seat_count" => 1}
      })

    assert conn.status == 404

    assert conn.resp_body == %{
             errors: [
               %{
                 status: "404",
                 code: "action_not_found",
                 title: "Not found",
                 detail: "open-registration is not a supported action for missing_handler_resource"
               }
             ]
           }
  end

  defp conn do
    %{
      assigns: %{
        authority: Hawk.Authority.new(:school_admin, Videdal.school_admin_id(), scopes: %{school_id: @school_id})
      },
      status: nil,
      resp_body: nil
    }
  end
end
