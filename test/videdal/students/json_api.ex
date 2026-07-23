defmodule Videdal.Students.JsonApi do
  @moduledoc """
  JSON:API adapter contract for the Videdal students resource.
  """

  use Hawk.JsonApi.Resource

  type("students")
  doc("A student enrolled at a school.")

  attribute(:name,
    writable: true,
    doc: "Student display name used in course and grade views.",
    example: "Ada"
  )

  attribute(:active,
    writable: true,
    doc: "Whether the student is currently active and visible to student-scoped reads.",
    example: true
  )

  relationship(:school,
    writable: true,
    doc: "The school this student belongs to.",
    example: %{type: "schools", id: "7"}
  )

  relationship(:grades,
    doc: "Grades awarded to this student, policy-filtered by the requesting authority.",
    example: [%{type: "grades", id: "1"}]
  )

  relationship(:parents,
    doc: "Parents and guardians linked to this student through internal access links.",
    example: [%{type: "parents", id: "4"}]
  )
end
