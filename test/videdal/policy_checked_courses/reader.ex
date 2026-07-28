defmodule Videdal.PolicyCheckedCourses.Reader do
  @moduledoc false

  use Hawk.Reader.Resource,
    repo: Videdal.Repo,
    schema: Videdal.Course,
    policy: Videdal.Courses.Policy

  filter(:id)
  filter(:school_id)
  filter(:teacher_id)

  sort(:id)
  sort(:title)
end
