defmodule Videdal.CourseGradeSummaries.Policy do
  use Hawk.Policy

  @moduledoc """
  Policy for read-only grade summary views.
  """

  read(:all)
  write(:never)
end
