defmodule Videdal.CourseGradeSummary do
  @moduledoc """
  Read-only course grade summary model backed by a database view in real apps.
  """

  use Hawk.Model

  @primary_key {:id, :integer, autogenerate: false}
  model "course_grade_summaries" do
    field(:school_id, :integer)
    field(:course_id, :integer)
    field(:grade_count, :integer)
    field(:average_score, :float)
  end
end
