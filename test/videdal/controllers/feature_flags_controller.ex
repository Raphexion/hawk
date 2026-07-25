defmodule Videdal.Controllers.FeatureFlagsController do
  @moduledoc false

  use Hawk.JsonApi.Controller,
    resource: Videdal.FeatureFlags,
    model: Videdal.FeatureFlag
end
