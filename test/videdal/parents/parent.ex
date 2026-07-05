defmodule Videdal.Parent do
  @moduledoc """
  Parent schema used by the Videdal example resources.
  """

  use Ecto.Schema

  schema "parents" do
    field(:name, :string)
    belongs_to(:school, Videdal.School)
    has_many(:parent_students, Videdal.ParentStudent)
  end
end
