defmodule Videdal.PolicyCheckedCourses do
  @moduledoc """
  Course resource backed by SandboxRepo for policy/filter integration tests.
  """

  use Hawk.Resource,
    model: Videdal.Course,
    json_api: false
end
