defmodule Videdal.Grades.JsonApi do
  @moduledoc """
  JSON:API adapter contract for the Videdal grades resource.
  """

  use Hawk.JsonApi.Resource

  type("grades")
  tag("Academics")
  group("Grades")
  doc("A grade awarded to a student for a course.")

  attribute(:score,
    writable: true,
    doc: "Numeric grade score awarded by the teacher.",
    example: 12
  )

  relationship(:student,
    creatable: true,
    doc: "The student who received the grade.",
    example: %{type: "students", id: "8"}
  )

  relationship(:course,
    creatable: true,
    doc: "The course where the grade was awarded.",
    example: %{type: "courses", id: "3"}
  )
end
