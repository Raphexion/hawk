defmodule Hawk.OpenApiResourceAdapterTest do
  use ExUnit.Case, async: true

  test "OpenAPI accepts resource facades and documents adapter JSON:API contract" do
    spec = Hawk.OpenApi.spec([Videdal.ExternalCourses])

    assert Map.has_key?(spec.paths, "/courses")
    refute Map.has_key?(spec.paths, "/internal_courses")

    course = Map.fetch!(spec.components.schemas, :ExternalCourseResource)

    assert course.description == "External course resource."
    assert course[:"x-resource-type"] == "courses"

    assert course.properties.attributes.properties == %{
             name: %{type: "string", description: "Public course name.", example: "Math"},
             slug: %{type: "string", description: "Public course slug.", example: "math"}
           }

    assert course.properties.relationships.properties.instructor == %{
             type: "string",
             description: "Public instructor relationship."
           }
  end

  test "write schemas use adapter names, source types, and capability metadata" do
    spec = Hawk.OpenApi.spec([Videdal.ExternalCourses])

    create_schema =
      spec.paths["/courses"].post.requestBody.content["application/vnd.api+json"].schema

    update_schema =
      spec.paths["/courses/{id}"].patch.requestBody.content["application/vnd.api+json"].schema

    assert create_schema.properties.data.properties.attributes.properties == %{
             name: %{type: "string", description: "Public course name.", example: "Math"},
             slug: %{type: "string", description: "Public course slug.", example: "math"}
           }

    assert update_schema.properties.data.properties.attributes.properties == %{
             name: %{type: "string", description: "Public course name.", example: "Math"}
           }

    assert create_schema.properties.data.properties.relationships.properties == %{
             instructor: %{type: "string", description: "Public instructor relationship."}
           }
  end

  test "include and sort parameters expose adapter names where applicable" do
    spec = Hawk.OpenApi.spec([Videdal.ExternalCourses])
    parameters = spec.paths["/courses"].get.parameters

    assert %{
             name: "include",
             in: "query",
             schema: %{type: "string", enum: ["instructor", "instructor.school"]}
           } in parameters

    assert %{
             name: "sort",
             in: "query",
             schema: %{type: "string", enum: ["public_slug", "-public_slug"]}
           } in parameters
  end

  test "OpenAPI omits resources with json_api disabled" do
    spec = Hawk.OpenApi.spec([Videdal.ExternalCourses, Videdal.InternalNotes])

    assert Map.has_key?(spec.paths, "/courses")
    refute Map.has_key?(spec.paths, "/internal_notes")
    assert Map.has_key?(spec.components.schemas, :ExternalCourseResource)
    refute Map.has_key?(spec.components.schemas, :InternalNoteResource)
  end

  test "OpenAPI exposes write routes and omits action routes when actions are absent" do
    spec = Hawk.OpenApi.spec([Videdal.CourseCatalog])

    assert spec.paths["/course-catalog"].get
    assert Map.has_key?(spec.paths["/course-catalog"], :post)

    assert spec.paths["/course-catalog/{id}"].get
    assert Map.has_key?(spec.paths["/course-catalog/{id}"], :patch)
    assert Map.has_key?(spec.paths["/course-catalog/{id}"], :delete)
    refute Map.has_key?(spec.paths, "/course-catalog/{id}/-actions/{action}")

    assert Map.has_key?(spec.paths, "/course-catalog/{id}/relationships/{relationship}")
    assert Map.has_key?(spec.paths, "/course-catalog/{id}/{relationship}")
  end
end
