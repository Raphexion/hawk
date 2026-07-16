defmodule Videdal.Courses do
  @moduledoc """
  Public facade for the Videdal `Courses` resource.
  """

  use Hawk.Resource,
    model: Videdal.Course
end
