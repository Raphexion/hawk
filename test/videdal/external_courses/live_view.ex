defmodule Videdal.ExternalCourses.LiveView do
  @moduledoc false

  use Hawk.LiveView.Resource

  as(:external_course)
  plural_as(:external_courses)
end
