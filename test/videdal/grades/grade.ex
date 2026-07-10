defmodule Videdal.Grade do
  @moduledoc """
  Grade schema used by the Videdal example resources.
  """

  use Hawk.Model

  model "grades" do
    field(:score, :integer)

    belongs_to(:school, Videdal.School)
    belongs_to(:student, Videdal.Student)
    belongs_to(:course, Videdal.Course)
  end

  json_api do
    type("grades")
    tag("Academics")
    group("Grades")
    doc("A grade awarded to a student for a course.")

    attribute(:score,
      doc: "Numeric grade score awarded by the teacher.",
      example: 12
    )

    relationship(:student,
      doc: "The student who received the grade.",
      example: %{type: "students", id: "8"}
    )

    relationship(:course,
      doc: "The course where the grade was awarded.",
      example: %{type: "courses", id: "3"}
    )

    creatable([:score, :student, :course])
    updatable([:score])
  end
end
