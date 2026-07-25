defmodule Videdal.Enrollments do
  @moduledoc """
  Public facade for the Videdal `Enrollments` resource.
  """

  use Hawk.Resource,
    model: Videdal.Enrollment,
    live_view: false
end
