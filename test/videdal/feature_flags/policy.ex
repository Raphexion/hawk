defmodule Videdal.FeatureFlags.Policy do
  use Hawk.Policy

  @moduledoc false

  read do
    role(:system, :all)
  end
end
