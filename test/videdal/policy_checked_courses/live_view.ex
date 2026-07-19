defmodule Videdal.PolicyCheckedCourses.LiveView do
  @moduledoc false

  use Hawk.LiveView.Resource

  as(:course)
  plural_as(:courses)

  index do
    filter(:teacher_id)

    table do
      column(:title)
      column(:teacher_id)
    end
  end
end
