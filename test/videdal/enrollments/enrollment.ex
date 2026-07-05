defmodule Videdal.Enrollment do
  @moduledoc """
  Enrollment schema connecting students to courses in the Videdal example.
  """

  use Hawk.Model

  model "enrollments" do
    field(:enrolled_on, :date)

    belongs_to(:school, Videdal.School)
    belongs_to(:student, Videdal.Student)
    belongs_to(:course, Videdal.Course)
  end
end
