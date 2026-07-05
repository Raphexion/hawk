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

    belongs_to(:school, Videdal.School,
      policy: Videdal.Schools.Policy,
      reader: Videdal.Schools.Reader
    )

    has_many(:grades, Videdal.Grade, policy: Videdal.Grades.Policy, reader: Videdal.Grades.Reader)

    has_many(:parent_students, Videdal.ParentStudent,
      policy: Videdal.Parents.Policy,
      reader: Videdal.Parents.Reader
    )
  end
end
