defmodule Hawk.ControllerBoundaryPathsTest.CoursesController do
  use Hawk.JsonApi.Controller,
    resource: Videdal.Courses,
    model: Videdal.Course
end

defmodule Hawk.ControllerBoundaryPathsTest.ErrorResource do
  def create(_attrs, _authority), do: {:error, "database unavailable"}
end

defmodule Hawk.ControllerBoundaryPathsTest.OkDeleteResource do
  def one(_opts), do: {:ok, %Videdal.Course{id: 3, title: "Math", school_id: 7, teacher_id: 12}}
  def delete(_course, _authority), do: :ok
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

defmodule Hawk.ControllerBoundaryPathsTest do
  use ExUnit.Case, async: true

  test "delete can return an empty JSON:API data document" do
    conn = Hawk.ControllerBoundaryPathsTest.OkDeleteController.delete(conn(), %{"id" => "3"})

    assert conn.status == 200
    assert conn.resp_body == %{data: nil}
  end

  test "delete returns not found through the controller boundary" do
    Process.put({Videdal.Repo, :all_results}, [])

    conn = Hawk.ControllerBoundaryPathsTest.CoursesController.delete(conn(), %{"id" => "missing"})

    assert conn.status == 404
    assert [%{status: "404", code: "not_found"}] = conn.resp_body.errors
  end

  test "resource errors become JSON:API 500 errors" do
    conn =
      Hawk.ControllerBoundaryPathsTest.ErrorController.create(conn(), %{
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

  defp conn do
    %{
      assigns: %{authority: Hawk.Authority.new(:school_admin, 1, scopes: %{school_id: 7})},
      status: nil,
      resp_body: nil
    }
  end
end
