defmodule Videdal.CourseRosters.LiveView do
  @moduledoc false

  use Hawk.LiveView.Resource

  as(:roster)
  plural_as(:rosters)

  show do
    field(:title)
    field(:enrollment_count, label: "Enrolled")
  end
end
