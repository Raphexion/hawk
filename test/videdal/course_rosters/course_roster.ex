defmodule Videdal.CourseRoster do
  @moduledoc """
  Projection fixture for declared-identity resources.

  Backed by a denormalized view keyed by `course_id` rather than a surrogate
  `:id`. Declares `primary_key: false` and exposes `:course_id` as the Hawk
  resource identity, proving every adapter stops assuming `:id`.
  """

  use Hawk.Model

  model "course_rosters", primary_key: false do
    field(:course_id, :binary_id)
    field(:title, :string)
    field(:enrollment_count, :integer)
  end
end
