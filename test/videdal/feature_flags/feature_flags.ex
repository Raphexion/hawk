defmodule Videdal.FeatureFlags do
  @moduledoc """
  Public facade for the Videdal `FeatureFlags` resource.

  A non-Ecto read-only resource backed by ETS. No writer or LiveView —
  the data is populated out of band and served read-only over JSON:API.
  """

  use Hawk.Resource,
    model: Videdal.FeatureFlag,
    writer: false,
    live_view: false
end
