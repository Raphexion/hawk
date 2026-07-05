defmodule Videdal.ParentStudent do
  @moduledoc """
  Join schema connecting parents to students in the Videdal example.
  """

  use Ecto.Schema

  schema "parent_students" do
    belongs_to(:parent, Videdal.Parent)
    belongs_to(:student, Videdal.Student)
    belongs_to(:school, Videdal.School)
  end
end
