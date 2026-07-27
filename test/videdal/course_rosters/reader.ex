defmodule Videdal.CourseRosters.Reader do
  @moduledoc false

  use Hawk.Reader.Resource,
    repo: Videdal.Repo,
    schema: Videdal.CourseRoster,
    default_sort: [asc: :course_id]

  filter(:course_id)
  sort(:course_id)
end
