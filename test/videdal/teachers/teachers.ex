defmodule Videdal.Teachers do
  @moduledoc """
  Public facade for the Videdal `Teachers` resource.
  """

  use Hawk.Resource,
    model: Videdal.Teacher,
    live_view: false
end
