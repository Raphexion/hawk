defmodule Hawk.JsonApiTest do
  use ExUnit.Case, async: true

  test "models expose explicit JSON:API metadata with rich field docs" do
    assert Videdal.Grade.__hawk_json_api__() == %{
             type: "grades",
             doc: "A grade awarded to a student for a course.",
             attributes: %{
               score: %{
                 doc: "Numeric grade score awarded by the teacher.",
                 example: 12
               }
             },
             relationships: %{
               student: %{
                 doc: "The student who received the grade.",
                 example: %{type: "students", id: "8"}
               },
               course: %{
                 doc: "The course where the grade was awarded.",
                 example: %{type: "courses", id: "3"}
               }
             },
             creatable: [:score, :student, :course],
             updatable: [:score]
           }
  end

  test "all Videdal resources have explicit JSON:API documentation" do
    models = [
      Videdal.School,
      Videdal.Student,
      Videdal.Course,
      Videdal.Teacher,
      Videdal.Enrollment,
      Videdal.Parent,
      Videdal.ParentStudent,
      Videdal.Grade,
      Videdal.CourseGradeSummary
    ]

    for model <- models do
      metadata = model.__hawk_json_api__()

      assert is_binary(metadata.type) and metadata.type != ""
      assert is_binary(metadata.doc) and metadata.doc != ""
      assert map_size(metadata.attributes) + map_size(metadata.relationships) > 0
    end
  end

  test "OpenAPI schema generation includes descriptions and examples" do
    schema = Hawk.JsonApi.openapi_schema(Videdal.Grade)

    assert schema["type"] == "object"
    assert schema["description"] == "A grade awarded to a student for a course."

    assert schema["properties"]["score"] == %{
             "description" => "Numeric grade score awarded by the teacher.",
             "example" => 12
           }

    assert schema["properties"]["student"] == %{
             "description" => "The student who received the grade.",
             "example" => %{type: "students", id: "8"}
           }
  end
end
