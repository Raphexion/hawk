defmodule Videdal.Enrollment do
  @moduledoc """
  Enrollment schema connecting students to courses in the Videdal example.
  """

  use Hawk.Model

  model "enrollments" do
    field(:enrolled_on, :date)

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
