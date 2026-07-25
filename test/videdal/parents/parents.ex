defmodule Videdal.Parents do
  @moduledoc """
  Public facade for the Videdal `Parents` resource.
  """

  use Hawk.Resource,
    model: Videdal.Parent,
    live_view: false
end
