defmodule Videdal.Integration.PlansPreview.Schools.Writer do
  @moduledoc false
  use Hawk.Writer.Resource,
    model: Videdal.School,
    repo: Videdal.SandboxRepo,
    policy: Videdal.Integration.PlansPreview.Schools.Policy

  create do
    cast([:name])
    validate_required([:name])
  end

  update do
    cast([:name])
  end

  delete(:default)
end
