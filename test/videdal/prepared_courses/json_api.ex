defmodule Videdal.PreparedCourses.JsonApi do
  @moduledoc false

  use Hawk.JsonApi.Resource

  type("prepared-courses")

  attribute(:title, [])
end
