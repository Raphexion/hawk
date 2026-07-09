defmodule Videdal.Teacher do
  @moduledoc """
  Teacher schema used by the Videdal example resources.
  """

  use Hawk.Model

  model "teachers" do
    field(:name, :string)

    belongs_to(:school, Videdal.School)
  end

  json_api do
    type("teachers")
    doc("A teacher who can teach courses and manage grades.")

    attribute(:name,
      doc: "Teacher display name.",
      example: "Grace Hopper"
    )

    relationship(:school,
      doc: "The school this teacher belongs to.",
      example: %{type: "schools", id: "7"}
    )

    creatable([:name, :school])
    updatable([:name, :school])
  end
end
