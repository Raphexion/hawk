defmodule Videdal.PreparedCourses do
  @moduledoc false

  use Hawk.Resource,
    model: Videdal.Course,
    live_view: false
end
