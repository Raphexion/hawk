defmodule Videdal.Controllers.OpenApiController do
  use Hawk.OpenApi.Controller,
    title: "Videdal API",
    version: "1.0.0",
    resources: [Videdal.Course, Videdal.Grade]
end

defmodule Videdal.Controllers.OpenApiControllerTest do
  use ExUnit.Case, async: true

  alias Videdal.Controllers.OpenApiController

  test "serves one OpenAPI document composed from listed Hawk resources" do
    conn = OpenApiController.show(conn(), %{})

    assert conn.status == 200
    assert conn.resp_body.openapi == "3.1.0"
    assert conn.resp_body.info == %{title: "Videdal API", version: "1.0.0"}

    assert Map.has_key?(conn.resp_body.paths, "/courses")
    assert Map.has_key?(conn.resp_body.paths, "/courses/{id}")
    assert Map.has_key?(conn.resp_body.paths, "/grades")
    assert Map.has_key?(conn.resp_body.components.schemas, :CourseResource)
    assert Map.has_key?(conn.resp_body.components.schemas, :GradeResource)
  end

  test "index operations expose JSON:API query parameters from reader and relationships" do
    spec = OpenApiController.spec()
    parameters = spec.paths["/courses"].get.parameters

    assert %{
             name: "include",
             in: "query",
             schema: %{
               enum: [
                 "grades",
                 "grades.course",
                 "grades.student",
                 "school",
                 "teacher",
                 "teacher.school"
               ]
             }
           } in parameters

    assert %{name: "sort", in: "query", schema: %{enum: ["id", "-id", "title", "-title"]}} in parameters

    assert %{name: "page[size]", in: "query", schema: %{type: "integer", minimum: 0}} in parameters
  end

  test "resource schemas include docs, examples, attributes, and relationships" do
    spec = OpenApiController.spec()
    course = Map.fetch!(spec.components.schemas, :CourseResource)

    assert course.description == "A course taught by a teacher at a school."

    assert course.properties.attributes.properties.title == %{
             type: "string",
             description: "Human-readable course title.",
             example: "Math"
           }

    assert course.properties.relationships.properties.teacher.description ==
             "The teacher responsible for the course."
  end

  test "write operations use creatable and updatable JSON:API request schemas" do
    spec = OpenApiController.spec()

    create_schema =
      spec.paths["/courses"].post.requestBody.content["application/vnd.api+json"].schema

    update_schema =
      spec.paths["/courses/{id}"].patch.requestBody.content["application/vnd.api+json"].schema

    assert create_schema.properties.data.properties.attributes.properties == %{
             title: %{
               type: "string",
               description: "Human-readable course title.",
               example: "Math"
             }
           }

    assert update_schema.properties.data.properties.attributes.properties == %{
             title: %{
               type: "string",
               description: "Human-readable course title.",
               example: "Math"
             }
           }
  end

  defp conn do
    %{assigns: %{}, status: nil, resp_body: nil}
  end
end
