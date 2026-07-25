defmodule Videdal.CourseGradeSummaries do
  @moduledoc """
  Public facade for the Videdal `CourseGradeSummaries` resource.
  """

  use Hawk.Resource,
    model: Videdal.CourseGradeSummary,
    live_view: false
end
