defmodule Videdal.Parent do
  @moduledoc """
  Parent schema used by the Videdal example resources.
  """

  use Hawk.Model

  model "parents" do
    field(:name, :string)

    belongs_to(:school, Videdal.School)

    has_many(:parent_students, Videdal.ParentStudent,
      policy: Videdal.Parents.Policy,
      reader: Videdal.Parents.Reader
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

    relationship(:parent_students,
      doc: "Links from this parent to the students they can access.",
      example: [%{type: "parent-students", id: "1"}]
    )

    creatable([:name, :school])
    updatable([:name, :school])
  end
end
