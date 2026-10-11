defmodule Videdal.CourseGradeProjection do
  @moduledoc false

  use Hawk.Model

  model "course_grade_projections" do
    field(:course_id, :binary_id)
    field(:school_id, :binary_id)
    field(:grade_count, :integer)

    has_many(:grades, Videdal.Grade, foreign_key: :course_id)
  end
end
