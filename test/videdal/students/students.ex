defmodule Videdal.Students do
  @moduledoc """
  Public facade for the Videdal `Students` resource.
  """

  use Hawk.Resource,
    model: Videdal.Student,
    live_view: false
end
