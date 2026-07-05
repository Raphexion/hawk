defmodule Videdal.CourseGradeSummaries.Reader do
  @moduledoc """
  Reader declaration module for the read-only Videdal course grade summaries.
  """

  use Hawk.Reader.Resource,
    repo: Videdal.Repo,
    schema: Videdal.CourseGradeSummary,
    policy: Videdal.CourseGradeSummaries.Policy

  filter(:school_id)
  filter(:course_id)
end
