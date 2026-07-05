defmodule Videdal.Student do
  @moduledoc """
  Student model for the Videdal `Students` resource.

  The model owns schema shape and pure student behavior. Query construction,
  authorization, and mutation orchestration live in sibling resource modules.
  """

  use Hawk.Model

  model "students" do
    field(:name, :string)
    field(:active, :boolean, default: true)

    belongs_to(:school, Videdal.School)
    has_many(:grades, Videdal.Grade)

    has_many(:parent_students, Videdal.ParentStudent,
      policy: Videdal.Parents.Policy,
      reader: Videdal.Parents.Reader
    )
  end

  json_api do
    type("students")
    doc("A student enrolled at a school.")

    attribute(:name,
      doc: "Student display name used in course and grade views.",
      example: "Ada"
    )

    attribute(:active,
      doc: "Whether the student is currently active and visible to student-scoped reads.",
      example: true
    )

    relationship(:school,
      doc: "The school this student belongs to.",
      example: %{type: "schools", id: "7"}
    )

    relationship(:grades,
      doc: "Grades awarded to this student, policy-filtered by the requesting authority.",
      example: [%{type: "grades", id: "1"}]
    )

    creatable([:name, :active, :school])
    updatable([:name, :active, :school])
  end
end
