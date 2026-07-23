defmodule Videdal.Enrollments.JsonApi do
  @moduledoc """
  JSON:API adapter contract for the Videdal enrollments resource.
  """

  use Hawk.JsonApi.Resource

  type("enrollments")
  doc("A student's enrollment in a course.")

  attribute(:enrolled_on,
    writable: true,
    doc: "Date when the student was enrolled in the course.",
    example: "2026-01-01"
  )

  attribute(:registration_status,
    doc: "Pending, enrolled, waitlisted, or rejected registration outcome for the student.",
    example: "waitlisted"
  )

  relationship(:school,
    creatable: true,
    doc: "The school where the enrollment belongs.",
    example: %{type: "schools", id: "7"}
  )

  relationship(:student,
    creatable: true,
    doc: "The enrolled student.",
    example: %{type: "students", id: "8"}
  )

  relationship(:course,
    writable: true,
    doc: "The course the student is enrolled in.",
    example: %{type: "courses", id: "3"}
  )
end
