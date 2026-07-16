defmodule Videdal.ExternalCourses do
  @moduledoc """
  Resource facade used by adapter-contract tests.
  """

  use Hawk.Resource,
    model: Videdal.ExternalCourse
end
