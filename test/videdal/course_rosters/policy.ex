defmodule Videdal.CourseRosters.Policy do
  @moduledoc false

  use Hawk.Policy

  read(:all)
  write(:never)
end
