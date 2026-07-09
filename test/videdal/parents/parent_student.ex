defmodule Videdal.ParentStudent do
  @moduledoc """
  Join schema connecting parents to students in the Videdal example.
  """

  use Hawk.Model

  model "parent_students" do
    belongs_to(:parent, Videdal.Parent)
    belongs_to(:student, Videdal.Student)
    belongs_to(:school, Videdal.School)
  end

  json_api do
    type("parent-students")
    doc("A link granting a parent access to a student.")

    relationship(:parent,
      doc: "The parent or guardian receiving access.",
      example: %{type: "parents", id: "4"}
    )

    relationship(:student,
      doc: "The student visible to the parent.",
      example: %{type: "students", id: "8"}
    )

    relationship(:school,
      doc: "The school shared by the parent and student link.",
      example: %{type: "schools", id: "7"}
    )

    creatable([:parent, :student, :school])
    updatable([])
  end
end
