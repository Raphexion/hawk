defmodule Videdal.CourseGradeSummaries.JsonApi do
  @moduledoc """
  JSON:API adapter contract for the read-only course grade summary resource.
  """

  use Hawk.JsonApi.Resource

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
end
