defmodule Videdal.Integration.PlansPreview.Schools.Policy do
  @moduledoc false
  use Hawk.Policy

  read do
    role(:system, :all)
  end

  write(roles: [:system])
end
