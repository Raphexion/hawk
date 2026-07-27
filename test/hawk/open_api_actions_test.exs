defmodule Hawk.OpenApiActionsTest do
  use ExUnit.Case, async: true

  # Videdal.Courses is a full Hawk.Resource facade (reader + writer + policy
  # + actions) — the shape EPI uses. Its `open-registration` action exercises
  # the OpenAPI action-param → JSON schema mapping without a dedicated
  # reader-less test fixture.

  test "OpenAPI resolves to-one relationships to typed resource identifier schemas" do
    spec = Hawk.OpenApi.spec([Videdal.Courses])
    course = Map.fetch!(spec.components.schemas, :CourseResource)
    teacher = course.properties.relationships.properties.teacher

    assert teacher.type == "object"
    assert teacher.description == "The teacher responsible for the course."

    assert teacher.properties.data == %{
             type: "object",
             properties: %{
               id: %{type: "string"},
               type: %{type: "string", enum: ["teachers"]}
             }
           }
  end

  test "OpenAPI resolves to-many relationships to typed array schemas" do
    spec = Hawk.OpenApi.spec([Videdal.Courses])
    course = Map.fetch!(spec.components.schemas, :CourseResource)
    grades = course.properties.relationships.properties.grades

    assert grades.type == "object"

    assert grades.properties.data == %{
             type: "array",
             items: %{
               type: "object",
               properties: %{
                 id: %{type: "string"},
                 type: %{type: "string", enum: ["grades"]}
               }
             }
           }
  end

  test "OpenAPI action schemas map Hawk action param types to JSON schema types" do
    spec = Hawk.OpenApi.spec([Videdal.Courses])

    action = spec.paths["/courses/{id}/-actions/open-registration"].post
    meta = action.requestBody.content["application/vnd.api+json"].schema.properties.meta

    assert meta.properties == %{
             seat_count: %{
               type: "integer",
               description: "Seats offered immediately when registration opens.",
               example: 2
             },
             waitlist_count: %{
               type: "integer",
               description: "How many waitlist places should be tracked for this course.",
               example: 1
             }
           }
  end
end
