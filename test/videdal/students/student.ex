defmodule Videdal.Student do
  @moduledoc """
  Student model for the Videdal `Students` resource.

  The model owns schema shape and pure student behavior. Query construction,
  authorization, and mutation orchestration live in sibling resource modules.
  """

  use Hawk.Model

  model "students" do
    field(:name, :string)
    field(:active, :boolean, default: true)

    belongs_to(:school, Videdal.School)
    has_many(:grades, Videdal.Grade)

    has_many(:parent_students, Videdal.ParentStudent)

    many_to_many(:parents, Videdal.Parent,
      join_through: Videdal.ParentStudent,
      join_keys: [student_id: :id, parent_id: :id],
      policy: Videdal.Parents.Policy,
      reader: Videdal.Parents.Reader
    )
  end
end
