defmodule Hawk.PhoenixIntegrationTest.CoursesController do
  @moduledoc false

  use Hawk.JsonApi.Controller,
    resource: Videdal.Courses,
    model: Videdal.Course
end

defmodule Hawk.PhoenixIntegrationTest.OpenApiController do
  @moduledoc false

  use Hawk.OpenApi.Controller,
    title: "Integration API",
    version: "1.0.0",
    resources: [Videdal.Courses]
end

defmodule Hawk.PhoenixIntegrationTest do
  use ExUnit.Case, async: true

  # Phoenix is a required dependency. These tests exercise the real
  # `%Plug.Conn{}` and `%Phoenix.LiveView.Socket{}` code paths that Hawk calls
  # directly.

  alias Hawk.Authority
  alias Hawk.PhoenixIntegrationTest.{CoursesController, OpenApiController}
  alias Videdal.{Course, LiveViews.CourseLive}

  @course_id Videdal.course_id()
  @school_id Videdal.school_id()
  @teacher_id Videdal.teacher_id()

  test "JSON:API controller renders through a real Plug.Conn with the JSON:API content type" do
    course = %Course{id: @course_id, title: "Math", school_id: @school_id, teacher_id: @teacher_id}
    Process.put({Videdal.Repo, :all_results}, [course])

    conn =
      Plug.Test.conn(:get, "/courses")
      |> Plug.Conn.assign(:authority, Authority.system())
      |> CoursesController.index(%{})

    assert conn.status == 200
    assert conn.state == :sent

    [content_type] = Plug.Conn.get_resp_header(conn, "content-type")
    assert String.starts_with?(content_type, "application/vnd.api+json")

    assert %{"data" => [%{"type" => "courses", "id" => id}]} = Jason.decode!(conn.resp_body)
    assert id == @course_id
  end

  test "OpenAPI controller renders through a real Plug.Conn" do
    conn =
      Plug.Test.conn(:get, "/openapi.json")
      |> OpenApiController.show(%{})

    assert conn.status == 200
    assert conn.state == :sent

    assert %{"openapi" => "3.1.0", "info" => %{"title" => "Integration API"}} =
             Jason.decode!(conn.resp_body)
  end

  test "LiveView index helpers assign through a real Phoenix.LiveView.Socket" do
    course = %Course{id: @course_id, title: "Math", school_id: @school_id, teacher_id: @teacher_id}
    Process.put({Videdal.Repo, :all_results}, [course])

    socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}}
    socket = CourseLive.assign_index(socket, Authority.system())

    assert socket.assigns.courses == [course]
    assert socket.assigns.hawk_resource == :course
  end

  test "LiveView form helpers build a Phoenix.HTML.Form through a real socket" do
    socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}}
    socket = CourseLive.assign_new_form(socket, Authority.system())

    assert match?(%Phoenix.HTML.Form{}, socket.assigns.course_form)
  end
end
