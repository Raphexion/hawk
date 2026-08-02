defmodule Videdal.Announcements.Policy do
  use Hawk.Policy

  @moduledoc false

  read do
    role(:system, :all)
    role(:public, :all)
  end

  write(roles: [:system])
end
