defmodule Videdal.Grades do
  @moduledoc """
  Public facade for the Videdal `Grades` resource.
  """

  use Hawk.Resource,
    model: Videdal.Grade,
    live_view: false
end
