defmodule Videdal.Course do
  @moduledoc """
  Course schema used by the Videdal example resources.
  """

  use Hawk.Model

  model "courses" do
    field(:title, :string)
    field(:registration_state, :string, default: "draft")
    field(:seat_count, :integer, default: 0)
    field(:waitlist_count, :integer, default: 0)

    belongs_to(:school, Videdal.School)
    belongs_to(:teacher, Videdal.Teacher)
    has_many(:grades, Videdal.Grade)
    has_many(:enrollments, Videdal.Enrollment)
  end
end
