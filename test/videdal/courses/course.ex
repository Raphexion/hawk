defmodule Videdal.Course do
  @moduledoc """
  Course schema used by the Videdal example resources.
  """

  use Hawk.Model

  model "courses" do
    field(:title, :string)
    field(:registration_state, :string, default: "draft")
    field(:seat_count, :integer, default: 0)
    field(:waitlist_count, :integer, default: 0)

    belongs_to(:school, Videdal.School)
    belongs_to(:teacher, Videdal.Teacher)
    has_many(:grades, Videdal.Grade)
    has_many(:enrollments, Videdal.Enrollment)
  end

  json_api do
    type("courses")
    tag("Academics")
    group("Courses")
    doc("A course taught by a teacher at a school.")

    attribute(:title,
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
      doc: "The school offering the course.",
      example: %{type: "schools", id: Videdal.school_id()}
    )

    relationship(:teacher,
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

    creatable([:title, :school, :teacher])
    updatable([:title, :school, :teacher])
  end
end
