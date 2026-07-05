defmodule Videdal.Student do
  @moduledoc """
  Student model for the Videdal `Students` resource.

  The model owns schema shape and pure student behavior. Query construction,
  authorization, and mutation orchestration live in sibling resource modules.
  """

  use Ecto.Schema

  schema "students" do
    field(:name, :string)
    field(:active, :boolean, default: true)
    belongs_to(:school, Videdal.School)
    has_many(:grades, Videdal.Grade)
    has_many(:parent_students, Videdal.ParentStudent)
  end
end
