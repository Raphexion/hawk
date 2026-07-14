defmodule Videdal.Enrollment do
  @moduledoc """
  Enrollment schema connecting students to courses in the Videdal example.
  """

  use Hawk.Model

  model "enrollments" do
    field(:enrolled_on, :date)
    field(:registration_status, :string, default: "pending")

    belongs_to(:school, Videdal.School)
    belongs_to(:student, Videdal.Student)
    belongs_to(:course, Videdal.Course)
  end

  json_api do
    type("enrollments")
    doc("A student's enrollment in a course.")

    attribute(:enrolled_on,
      doc: "Date when the student was enrolled in the course.",
      example: "2026-01-01"
    )

    attribute(:registration_status,
      doc: "Pending, enrolled, waitlisted, or rejected registration outcome for the student.",
      example: "waitlisted"
    )

    relationship(:school,
      doc: "The school where the enrollment belongs.",
      example: %{type: "schools", id: "7"}
    )

    relationship(:student,
      doc: "The enrolled student.",
      example: %{type: "students", id: "8"}
    )

    relationship(:course,
      doc: "The course the student is enrolled in.",
      example: %{type: "courses", id: "3"}
    )

    creatable([:school, :student, :course, :enrolled_on])
    updatable([:course, :enrolled_on])
  end
end
