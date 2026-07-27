defmodule Videdal.CourseRosters.JsonApi do
  @moduledoc false

  use Hawk.JsonApi.Resource

  type("course-rosters")
  doc("A course roster projection keyed by course_id.")

  attribute(:title,
    doc: "Course title as shown on the roster.",
    example: "Math"
  )

  attribute(:enrollment_count,
    doc: "Number of enrolled students.",
    example: 2
  )
end
