defmodule Hawk.JsonApi.SchemaMetadataTest do
  use ExUnit.Case, async: true

  # The sibling adapter is the single source of a resource's JSON:API shape.
  # These cover the adapter declarations that Schema.metadata resolves.

  test "the grades adapter exposes explicit JSON:API metadata with rich field docs" do
    assert Hawk.JsonApi.Schema.metadata(Videdal.Grade) == %{
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
      Videdal.Grade,
      Videdal.CourseGradeSummary
    ]

    for model <- models do
      metadata = Hawk.JsonApi.Schema.metadata(model)

      assert is_binary(metadata.type) and metadata.type != ""
      assert is_binary(metadata.doc) and metadata.doc != ""
      assert map_size(metadata.attributes) + map_size(metadata.relationships) > 0
    end
  end
end
