defmodule Videdal.PreparedCourses.Reader do
  @moduledoc false

  use Hawk.Reader.Resource,
    repo: Videdal.Repo,
    schema: Videdal.Course,
    policy: Videdal.PreparedCourses.Policy

  filter(:id)
  filter(:title)

  filter :prepared_marker do
    fn {:eq, marker} ->
      dynamic([], fragment("current_setting('hawk.similar_courses.marker', true) = ?", ^marker))
    end
  end

  sort(:id)
  sort(:title)
end
