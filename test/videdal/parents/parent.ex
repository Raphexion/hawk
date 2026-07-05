defmodule Videdal.Parent do
  @moduledoc """
  Parent schema used by the Videdal example resources.
  """

  use Hawk.Model

  model "parents" do
    field(:name, :string)

    belongs_to(:school, Videdal.School,
      policy: Videdal.Schools.Policy,
      reader: Videdal.Schools.Reader
    )

    has_many(:parent_students, Videdal.ParentStudent,
      policy: Videdal.Parents.Policy,
      reader: Videdal.Parents.Reader
    )
  end
end
