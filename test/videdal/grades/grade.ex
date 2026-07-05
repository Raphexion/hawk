defmodule Videdal.Grade do
  @moduledoc """
  Grade schema used by the Videdal example resources.
  """

  use Hawk.Model

  model "grades" do
    field(:score, :integer)
    belongs_to(:school, Videdal.School, policy: Videdal.Schools.Policy)
    belongs_to(:student, Videdal.Student, policy: Videdal.Students.Policy)
    belongs_to(:course, Videdal.Course, policy: Videdal.Courses.Policy)
  end
end
