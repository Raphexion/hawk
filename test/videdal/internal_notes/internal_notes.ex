defmodule Videdal.InternalNotes do
  @moduledoc """
  Read-only resource intentionally not exposed through JSON:API or LiveView.
  """

  use Hawk.Resource,
    model: Videdal.InternalNote,
    json_api: false,
    live_view: false
end
