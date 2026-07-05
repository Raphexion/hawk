defmodule Videdal.Course do
  @moduledoc """
  Course schema used by the Videdal example resources.
  """

  use Hawk.Model

  model "courses" do
    field(:title, :string)

    belongs_to(:school, Videdal.School,
      policy: Videdal.Schools.Policy,
      reader: Videdal.Schools.Reader
    )

    belongs_to(:teacher, Videdal.Teacher,
      policy: Videdal.Teachers.Policy,
      reader: Videdal.Teachers.Reader
    )

    has_many(:grades, Videdal.Grade, policy: Videdal.Grades.Policy, reader: Videdal.Grades.Reader)
  end
end
