defmodule Videdal.PreparedCourses.Policy do
  use Hawk.Policy

  @moduledoc false

  read do
    role(:public, :all)
  end

  write(:never)
end
