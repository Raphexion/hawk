defmodule Videdal.CourseGradeSummary do
  @moduledoc """
  Read-only course grade summary model backed by a database view in real apps.
  """

  use Videdal.Model

  @primary_key {:id, :integer, autogenerate: false}
  model "course_grade_summaries" do
    field(:school_id, :integer)
    field(:course_id, :integer)
    field(:grade_count, :integer)
    field(:average_score, :float)
  end

  json_api do
    type("course-grade-summaries")
    doc("Read-only aggregate grade statistics for a course.")

    attribute(:school_id,
      doc: "School identifier for the summarized course.",
      example: 7
    )

    attribute(:course_id,
      doc: "Course identifier the statistics describe.",
      example: 3
    )

    attribute(:grade_count,
      doc: "Number of grades included in the summary.",
      example: 2
    )

    attribute(:average_score,
      doc: "Average grade score for the course.",
      example: 11.0
    )

    creatable([])
    updatable([])
  end
end
