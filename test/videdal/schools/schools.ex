defmodule Videdal.Schools do
  @moduledoc """
  Public facade for the Videdal `Schools` resource.
  """

  use Hawk.Resource,
    model: Videdal.School,
    live_view: false
end
