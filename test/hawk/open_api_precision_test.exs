defmodule Hawk.OpenApiPrecisionTest do
  use ExUnit.Case, async: true

  alias Hawk.JsonApi.Request
  alias Hawk.Test.NonNullRelationshipPresentation

  test "pagination describes actual per-reader defaults and caps" do
    spec = Hawk.OpenApi.spec([Videdal.Courses, Videdal.Students], title: "Videdal API")
    courses = Enum.find(spec.paths["/courses"].get.parameters, &(Map.get(&1, :name) == "page[size]"))
    students = Enum.find(spec.paths["/students"].get.parameters, &(Map.get(&1, :name) == "page[size]"))
    assert courses.schema == %{type: "integer", minimum: 1, default: 10, maximum: 50}
    assert students.schema == %{type: "integer", minimum: 1, default: 100, maximum: 100}
    assert courses.schema.default == Videdal.Courses.Reader.default_page_size()
    assert courses.schema.maximum == Videdal.Courses.Reader.max_page_size()
  end

  test "required and nullable linkage are independent, including renamed relationships" do
    spec = Hawk.OpenApi.spec([Videdal.Courses], title: "Videdal API", presentation: NonNullRelationshipPresentation)

    properties =
      spec.paths["/courses"].post.requestBody.content["application/vnd.api+json"].schema.properties.data.properties.relationships

    assert properties.required == [:campus]
    campus = properties.properties.campus.properties.data
    assert campus.required == [:type, :id]
    refute Map.has_key?(campus, :anyOf)
    assert %{type: "null"} in properties.properties.teacher.properties.data.anyOf

    patch =
      spec.paths["/courses/{id}"].patch.requestBody.content["application/vnd.api+json"].schema.properties.data.properties.relationships

    refute Map.has_key?(patch, :required)
    assert patch.properties.campus.properties.data == campus
    # A required parent may be invisible to a reader's authority.
    read = spec.components.schemas[:CourseResource].properties.relationships.properties.campus.properties.data
    assert %{type: "null"} in read.anyOf
  end

  test "request validation enforces explicit non-null linkage without requiring its presence" do
    document = fn relationships -> %{"data" => %{"type" => "courses", "relationships" => relationships}} end
    opts = [presentation: NonNullRelationshipPresentation]

    assert_raise ArgumentError, ~r/campus.*must not be null/, fn ->
      Request.validate_document!(document.(%{"campus" => %{"data" => nil}}), Videdal.Course, :creatable, opts)
    end

    assert :ok =
             Request.validate_document!(document.(%{"teacher" => %{"data" => nil}}), Videdal.Course, :creatable, opts)

    assert :ok = Request.validate_document!(document.(%{}), Videdal.Course, :creatable, opts)
    # Existing adapters without an explicit constraint still accept null.
    assert :ok = Request.validate_document!(document.(%{"school" => %{"data" => nil}}), Videdal.Course, :creatable)

    assert_raise ArgumentError, ~r/campus.*must not be null/, fn ->
      document.(%{"campus" => %{"data" => nil}})
      |> put_in(["data", "id"], Ecto.UUID.generate())
      |> Request.validate_document!(Videdal.Course, :updatable, opts)
    end

    assert :ok =
             Request.validate_document!(
               document.(%{"campus" => %{"data" => %{"type" => "schools", "id" => Ecto.UUID.generate()}}}),
               Videdal.Course,
               :creatable,
               opts
             )
  end

  test "included resources use declared schemas with an unknown-type-only fallback" do
    spec = Hawk.OpenApi.spec([Videdal.Courses, Videdal.Students], title: "Videdal API")
    included = spec.components.schemas[:JsonApiIncludedResource]
    assert %{"$ref": "#/components/schemas/CourseResource"} in included.anyOf
    assert %{"$ref": "#/components/schemas/StudentResource"} in included.anyOf
    fallback = Enum.find(included.anyOf, &Map.has_key?(&1, :properties))
    assert fallback.properties.type.not.enum == ["courses", "students"]
    assert included.required == [:type, :id]
    assert fallback.properties.type.not.enum == Enum.sort(fallback.properties.type.not.enum)
    # No association crawling: undeclared related resources remain allowed.
    refute Map.has_key?(spec.components.schemas, :TeacherResource)
  end
end
