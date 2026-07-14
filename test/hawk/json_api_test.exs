defmodule Hawk.JsonApiTest do
  use ExUnit.Case, async: true

  test "models expose explicit JSON:API metadata with rich field docs" do
    assert Videdal.Grade.__hawk_json_api__() == %{
             type: "grades",
             tag: "Academics",
             group: "Grades",
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

  test "request options parse JSON:API filter params" do
    assert Hawk.JsonApi.request_options(%{
             "filter" => %{
               "school_id" => "school-1",
               "active" => %{"eq" => "true"},
               "name" => %{"ilike" => "%math%"}
             }
           }) == [filter: %{school_id: "school-1", active: {:eq, true}, name: {:ilike, "%math%"}}]
  end

  test "request options reject unsupported filter operators" do
    assert_raise ArgumentError, ~r/unsupported filter operator "starts_with"/, fn ->
      Hawk.JsonApi.request_options(%{"filter" => %{"name" => %{"starts_with" => "math"}}})
    end
  end

  test "JSON:API attribute extraction supports nil relationships and ignores undeclared ones" do
    attrs =
      Hawk.JsonApi.attributes(
        %{
          "data" => %{
            "type" => "courses",
            "attributes" => %{"title" => "Math"},
            "relationships" => %{
              "school" => %{"data" => nil},
              "teacher" => %{"data" => %{"type" => "teachers", "id" => "12"}},
              "grades" => %{"data" => [%{"type" => "grades", "id" => "1"}]}
            }
          }
        },
        Videdal.Course,
        :creatable
      )

    assert attrs == %{title: "Math", school_id: nil, teacher_id: 12}
  end
end
