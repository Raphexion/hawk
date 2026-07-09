defmodule Videdal.School do
  @moduledoc """
  School schema used by the Videdal example resources.
  """

  use Hawk.Model

  model "schools" do
    field(:name, :string)
  end

  json_api do
    type("schools")
    doc("A school in the Videdal example domain.")

    attribute(:name,
      doc: "Public school name shown to students, parents, and staff.",
      example: "Videdal Skole"
    )

    creatable([:name])
    updatable([:name])
  end
end
