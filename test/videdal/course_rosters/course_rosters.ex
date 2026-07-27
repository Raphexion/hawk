defmodule Videdal.CourseRosters do
  @moduledoc """
  Facade for the declared-identity `CourseRoster` projection.

  `identity: :course_id` is the whole point: the JSON:API `id`, member lookup,
  and short-id range all key off `:course_id` instead of the assumed `:id`.
  """

  use Hawk.Resource,
    model: Videdal.CourseRoster,
    identity: :course_id
end
