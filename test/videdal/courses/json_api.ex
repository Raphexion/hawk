defmodule Videdal.Courses.JsonApi do
  @moduledoc """
  JSON:API adapter contract for the Videdal courses resource.
  """

  use Hawk.JsonApi.Resource

  type("courses")
  tag("Academics", description: "Academic resources: courses, grades, and enrollments.")
  group("Courses")
  doc("A course taught by a teacher at a school.")

  attribute(:title,
    writable: true,
    doc: "Human-readable course title.",
    example: "Math"
  )

  attribute(:registration_state,
    doc: "Whether registration is draft, open, or closed for this course.",
    example: "open"
  )

  attribute(:seat_count,
    doc: "Number of seats available when registration is finalized.",
    example: 2
  )

  attribute(:waitlist_count,
    doc: "Number of students that may remain waitlisted after registration closes.",
    example: 1
  )

  relationship(:school,
    writable: true,
    doc: "The school offering the course.",
    example: %{type: "schools", id: Videdal.school_id()}
  )

  relationship(:teacher,
    writable: true,
    doc: "The teacher responsible for the course.",
    example: %{type: "teachers", id: Videdal.teacher_id()}
  )

  relationship(:grades,
    doc: "Grades awarded in this course, filtered through grade visibility rules.",
    example: [%{type: "grades", id: "1"}]
  )

  relationship(:enrollments,
    doc: "Registrations submitted for this course, including final enrollment outcomes.",
    example: [%{type: "enrollments", id: "6"}]
  )

  visibility do
    role(:public, hide: [:seat_count, :enrollments])
  end
end
