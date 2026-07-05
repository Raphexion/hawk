defmodule Videdal.ParentStudent do
  @moduledoc """
  Join schema connecting parents to students in the Videdal example.
  """

  use Hawk.Model

  model "parent_students" do
    belongs_to(:parent, Videdal.Parent,
      policy: Videdal.Parents.Policy,
      reader: Videdal.Parents.Reader
    )

    belongs_to(:student, Videdal.Student,
      policy: Videdal.Students.Policy,
      reader: Videdal.Students.Reader
    )

    belongs_to(:school, Videdal.School,
      policy: Videdal.Schools.Policy,
      reader: Videdal.Schools.Reader
    )
  end
end
