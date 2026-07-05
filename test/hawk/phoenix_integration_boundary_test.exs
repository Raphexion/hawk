defmodule Plug.Conn do
  @moduledoc false

  def put_status(conn, status), do: Map.put(conn, :status, status)
end

defmodule Phoenix.Controller do
  @moduledoc false

  def json(conn, body), do: conn |> Map.put(:phoenix_json, body) |> Map.put(:resp_body, body)
end

defmodule Phoenix.Component do
  @moduledoc false

  def assign(socket, key, value) do
    socket
    |> Map.update(:phoenix_assigned, [key], &[key | &1])
    |> Map.update(:assigns, %{key => value}, &Map.put(&1, key, value))
  end
end

defmodule Hawk.PhoenixIntegrationBoundaryTest.OpenApiController do
  use Hawk.OpenApi.Controller,
    title: "Phoenix Boundary API",
    version: "1.0.0",
    resources: [Videdal.Course]
end

defmodule Hawk.PhoenixIntegrationBoundaryTest.CoursesController do
  use Hawk.JsonApi.Controller,
    resource: Videdal.Courses,
    model: Videdal.Course
end

defmodule Hawk.PhoenixIntegrationBoundaryTest.CourseLive do
  use Hawk.LiveView,
    resource: Videdal.Courses,
    as: :course
end

defmodule Hawk.PhoenixIntegrationBoundaryTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Videdal.Course

  test "JSON:API controllers use Phoenix json when Phoenix is present" do
    courses = [%Course{id: 3, title: "Math", school_id: 7, teacher_id: 12}]
    Process.put({Videdal.Repo, :all_results}, courses)

    conn =
      Hawk.PhoenixIntegrationBoundaryTest.CoursesController.index(conn(), %{
        "include" => "teacher"
      })

    assert conn.status == 200

    assert conn.phoenix_json.data == [
             Hawk.JsonApi.document(hd(courses), preloads: [:teacher]).data
           ]
  end

  test "OpenAPI controllers use Phoenix json when Phoenix is present" do
    conn = Hawk.PhoenixIntegrationBoundaryTest.OpenApiController.show(conn(), %{})

    assert conn.status == 200
    assert conn.phoenix_json.openapi == "3.1.0"
  end

  test "LiveView helpers use Phoenix.Component.assign when Phoenix is present" do
    courses = [%Course{id: 3, title: "Math", school_id: 7, teacher_id: 12}]
    Process.put({Videdal.Repo, :all_results}, courses)

    socket =
      Hawk.PhoenixIntegrationBoundaryTest.CourseLive.assign_index(socket(), Authority.system())

    assert socket.assigns.courses == courses
    assert socket.phoenix_assigned == [:courses, :hawk_page, :hawk_resource]
  end

  defp conn do
    %{assigns: %{authority: Authority.system()}, status: nil, resp_body: nil}
  end

  defp socket, do: %{assigns: %{}, phoenix_assigned: []}
end
