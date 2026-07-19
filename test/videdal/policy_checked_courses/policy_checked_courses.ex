defmodule Videdal.PolicyCheckedCourses do
  @moduledoc """
  Course resource backed by SandboxRepo for policy/filter integration tests.
  """

  use Hawk.Resource,
    model: Videdal.Course,
    policy: Videdal.Courses.Policy,
    writer: false,
    json_api: false
end
