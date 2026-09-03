defmodule Hawk.OpenApiActionsTest do
  use ExUnit.Case, async: true

  # Videdal.Courses is a full Hawk.Resource facade (reader + writer + policy
  # + actions) — the shape EPI uses. Its `open-registration` action exercises
  # the OpenAPI action-param → JSON schema mapping without a dedicated
  # reader-less test fixture.

  test "OpenAPI omits nil resource descriptions" do
    spec = Hawk.OpenApi.spec([Videdal.PreparedCourses], title: "Test API")
    course = Map.fetch!(spec.components.schemas, :CourseResource)

    refute Map.has_key?(course, :description)
    refute Map.has_key?(course, :"x-resource-group")
  end

  test "OpenAPI resolves to-one relationships to typed resource identifier schemas" do
    spec = Hawk.OpenApi.spec([Videdal.Courses], title: "Test API")
    course = Map.fetch!(spec.components.schemas, :CourseResource)
    teacher = course.properties.relationships.properties.teacher

    assert teacher.type == "object"
    assert teacher.description == "The teacher responsible for the course."

    assert teacher.properties.data == %{
             anyOf: [
               %{
                 type: "object",
                 required: [:type, :id],
                 properties: %{
                   id: %{type: "string"},
                   type: %{type: "string", enum: ["teachers"]}
                 }
               },
               %{type: "null"}
             ]
           }
  end

  test "OpenAPI resolves to-many relationships to typed array schemas" do
    spec = Hawk.OpenApi.spec([Videdal.Courses], title: "Test API")
    course = Map.fetch!(spec.components.schemas, :CourseResource)
    grades = course.properties.relationships.properties.grades

    assert grades.type == "object"

    assert grades.properties.data == %{
             type: "array",
             items: %{
               type: "object",
               required: [:type, :id],
               properties: %{
                 id: %{type: "string"},
                 type: %{type: "string", enum: ["grades"]}
               }
             }
           }
  end

  test "OpenAPI action schemas map Hawk action param types to JSON schema types" do
    spec = Hawk.OpenApi.spec([Videdal.Courses], title: "Test API")

    action = spec.paths["/courses/{id}/-actions/open-registration"].post
    schema = action.requestBody.content["application/vnd.api+json"].schema
    meta = schema.properties.meta

    assert schema.required == [:meta]

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
