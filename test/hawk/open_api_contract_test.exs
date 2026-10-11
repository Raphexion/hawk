defmodule Hawk.OpenApiContractTest do
  use ExUnit.Case, async: true

  alias Hawk.JsonApi.Request
  alias Hawk.Test.OpenApiNullablePresentation

  test "nullable declarations retain UTC formats and ordinary fields remain non-null" do
    spec =
      Hawk.OpenApi.spec([Videdal.Students], title: "Test API", presentation: OpenApiNullablePresentation)

    attrs = spec.components.schemas[:StudentResource].properties.attributes.properties

    assert attrs.deleted_at == %{type: ["string", "null"], format: "date-time", description: "Deletion timestamp."}
    assert attrs.archived_at == %{type: "string", format: "date-time", description: "Archive timestamp."}
    assert OpenApiNullablePresentation.__hawk_json_api__().attributes.deleted_at.nullable
  end

  test "dates carry the date format" do
    spec = Hawk.OpenApi.spec([Videdal.Enrollments], title: "Test API")
    assert spec.components.schemas[:EnrollmentResource].properties.attributes.properties.enrolled_on.format == "date"
  end

  test "all generated secured operations describe authentication errors including deletes and actions" do
    spec = Hawk.OpenApi.spec([Videdal.Courses], title: "Test API", security: [%{"bearerAuth" => []}])

    for {_path, operations} <- spec.paths, {_method, operation} <- operations do
      assert operation.responses["401"].content["application/vnd.api+json"].schema == %{
               "$ref": "#/components/schemas/JsonApiErrorDocument"
             }
    end
  end

  test "public specs do not assume an authentication pipeline" do
    spec = Hawk.OpenApi.spec([Videdal.Courses], title: "Test API")
    refute Map.has_key?(spec.paths["/courses"].get.responses, "401")
  end

  test "combined includes and recursive paths are not constrained by a finite enum" do
    spec = Hawk.OpenApi.spec([Videdal.ExternalCourses], title: "Test API")

    for path <- ["/courses", "/courses/{id}"] do
      include = Enum.find(spec.paths[path].get.parameters, &(&1.name == "include"))
      assert include.schema == %{type: "string"}
    end

    assert Request.request_options(
             %{"include" => "instructor,instructor.campus"},
             reader: Videdal.ExternalCourses.Reader,
             model: Videdal.ExternalCourse
           ) == [preloads: [teacher: [:school]]]
  end
end
