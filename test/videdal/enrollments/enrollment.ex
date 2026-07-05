defmodule Videdal.Enrollment do
  @moduledoc """
  Enrollment schema connecting students to courses in the Videdal example.
  """

  use Hawk.Model

  model "enrollments" do
    field(:enrolled_on, :date)
    belongs_to(:school, Videdal.School, policy: Videdal.Schools.Policy)
    belongs_to(:student, Videdal.Student, policy: Videdal.Students.Policy)
    belongs_to(:course, Videdal.Course, policy: Videdal.Courses.Policy)
  end
end
