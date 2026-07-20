defmodule Videdal.Parent do
  @moduledoc """
  Parent schema used by the Videdal example resources.
  """

  use Hawk.Model

  model "parents" do
    field(:name, :string)

    belongs_to(:school, Videdal.School)

    has_many(:parent_students, Videdal.ParentStudent)

    many_to_many(:students, Videdal.Student,
      join_through: Videdal.ParentStudent,
      join_keys: [parent_id: :id, student_id: :id],
      policy: Videdal.Students.Policy,
      reader: Videdal.Students.Reader
    )
  end

  json_api do
    type("parents")
    doc("A parent or guardian linked to one or more students.")

    attribute(:name,
      doc: "Parent display name.",
      example: "Ada Parent"
    )

    relationship(:school,
      doc: "The school this parent belongs to.",
      example: %{type: "schools", id: "7"}
    )

    relationship(:students,
      doc: "Students this parent or guardian can access through internal links.",
      example: [%{type: "students", id: "8"}]
    )

    creatable([:name, :school])
    updatable([:name, :school])
  end
end
