defmodule Videdal.FeatureFlags.JsonApi do
  @moduledoc false

  use Hawk.JsonApi.Resource

  type("feature_flags")
  doc("A feature flag served from an ETS read model (non-Ecto pathfinder).")

  attribute(:key, doc: "Flag key, e.g. :new_dashboard")
  attribute(:enabled, doc: "Whether the flag is currently active.")
  attribute(:description, doc: "Human-readable explanation of the flag.")
end
