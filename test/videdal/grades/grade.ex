defmodule Videdal.Grade do
  @moduledoc """
  Grade schema used by the Videdal example resources.
  """

  use Hawk.Model

  model "grades" do
    field(:score, :integer)

    belongs_to(:school, Videdal.School,
      policy: Videdal.Schools.Policy,
      reader: Videdal.Schools.Reader
    )

    belongs_to(:student, Videdal.Student,
      policy: Videdal.Students.Policy,
      reader: Videdal.Students.Reader
    )

    belongs_to(:course, Videdal.Course,
      policy: Videdal.Courses.Policy,
      reader: Videdal.Courses.Reader
    )
  end
end
