defmodule Videdal.CourseGradeSummary do
  @moduledoc """
  Read-only course grade summary model backed by a database view in real apps.
  """

  use Hawk.Model

  model "course_grade_summaries" do
    field(:school_id, :binary_id)
    field(:course_id, :binary_id)
    field(:grade_count, :integer)
    field(:average_score, :float)
  end
end
