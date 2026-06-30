defmodule Videdal.Enrollment do
  @moduledoc """
  Join schema connecting students to courses.
  """

  use Ecto.Schema

  schema "enrollments" do
    field(:enrolled_on, :date)
    belongs_to(:school, Videdal.School)
    belongs_to(:student, Videdal.Student)
    belongs_to(:course, Videdal.Course)
  end
end
