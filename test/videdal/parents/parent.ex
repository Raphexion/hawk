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
end
