defmodule Hawk.PhoenixIntegrationTest.CoursesController do
  @moduledoc false

  use Hawk.JsonApi.Controller,
    resource: Videdal.Courses
end

defmodule Hawk.PhoenixIntegrationTest.OpenApiController do
  @moduledoc false

  use Hawk.OpenApi.Controller,
    title: "Integration API",
    version: "1.0.0",
    resources: [Videdal.Courses]
end

defmodule Hawk.PhoenixIntegrationTest do
  use Videdal.DatabaseCase, async: true

  alias Hawk.Authority
  alias Hawk.PhoenixIntegrationTest.{CoursesController, OpenApiController}
  alias Videdal.LiveViews.CourseLive

  test "JSON:API controller renders through a real Plug.Conn with the JSON:API content type" do
    course = insert(:course, title: "Math")

    conn =
      Plug.Test.conn(:get, "/courses")
      |> Plug.Conn.assign(:hawk_authority, Authority.system())
      |> CoursesController.index(%{})

    assert conn.status == 200
    assert conn.state == :sent

    assert Plug.Conn.get_resp_header(conn, "content-type") == ["application/vnd.api+json"]

    assert %{"data" => [%{"type" => "courses", "id" => id}]} = Jason.decode!(conn.resp_body)
    assert id == course.id
  end

  test "JSON:API controller reads the authority assigned by Hawk.Authority.Plug" do
    course = insert(:course, title: "Math")

    conn =
      Plug.Test.conn(:get, "/courses")
      |> Hawk.Authority.Plug.call(resolver: fn _conn -> Authority.system() end)
      |> CoursesController.index(%{})

    assert conn.status == 200
    assert %{"data" => [%{"id" => id}]} = Jason.decode!(conn.resp_body)
    assert id == course.id
  end

  test "JSON:API controller rejects unsupported Content-Type parameters" do
    conn =
      Plug.Test.conn(:post, "/courses", "")
      |> Plug.Conn.put_req_header("content-type", "application/vnd.api+json; charset=utf-8")
      |> Plug.Conn.assign(:hawk_authority, Authority.system())
      |> CoursesController.create(%{})

    assert conn.status == 415
    assert %{"errors" => [%{"status" => "415"}]} = Jason.decode!(conn.resp_body)
  end

  test "JSON:API controller rejects unsupported Content-Type on bodyless requests" do
    conn =
      Plug.Test.conn(:get, "/courses")
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> Plug.Conn.assign(:hawk_authority, Authority.system())
      |> CoursesController.index(%{})

    assert conn.status == 415
    assert %{"errors" => [%{"status" => "415"}]} = Jason.decode!(conn.resp_body)
  end

  test "JSON:API controller rejects an unacceptable JSON:API media type" do
    conn =
      Plug.Test.conn(:get, "/courses")
      |> Plug.Conn.put_req_header("accept", "application/vnd.api+json; charset=utf-8")
      |> Plug.Conn.assign(:hawk_authority, Authority.system())
      |> CoursesController.index(%{})

    assert conn.status == 406
    assert %{"errors" => [%{"status" => "406"}]} = Jason.decode!(conn.resp_body)
  end

  test "JSON:API controller accepts a valid media range beside an invalid one" do
    conn =
      Plug.Test.conn(:get, "/courses")
      |> Plug.Conn.put_req_header(
        "accept",
        "application/vnd.api+json; charset=utf-8, application/vnd.api+json; q=0.9"
      )
      |> Plug.Conn.assign(:hawk_authority, Authority.system())
      |> CoursesController.index(%{})

    assert conn.status == 200
  end

  test "JSON:API controller respects a more specific q=0 over a wildcard" do
    conn =
      Plug.Test.conn(:get, "/courses")
      |> Plug.Conn.put_req_header("accept", "application/vnd.api+json; q=0, */*; q=1")
      |> Plug.Conn.assign(:hawk_authority, Authority.system())
      |> CoursesController.index(%{})

    assert conn.status == 406
  end

  test "OpenAPI controller renders through a real Plug.Conn" do
    conn =
      Plug.Test.conn(:get, "/openapi.json")
      |> OpenApiController.show(%{})

    assert conn.status == 200
    assert conn.state == :sent

    [content_type] = Plug.Conn.get_resp_header(conn, "content-type")
    assert String.starts_with?(content_type, "application/json")

    assert %{"openapi" => "3.1.0", "info" => %{"title" => "Integration API"}} =
             Jason.decode!(conn.resp_body)
  end

  test "LiveView index helpers assign through a real Phoenix.LiveView.Socket" do
    insert(:course, title: "Math")

    socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}}
    socket = CourseLive.assign_index(socket, Authority.system())

    assert length(socket.assigns.courses) == 1
    assert socket.assigns.hawk_resource == :course
  end

  test "LiveView form helpers build a Phoenix.HTML.Form through a real socket" do
    socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}}
    socket = CourseLive.assign_new_form(socket, Authority.system())

    assert match?(%Phoenix.HTML.Form{}, socket.assigns.course_form)
  end
end
