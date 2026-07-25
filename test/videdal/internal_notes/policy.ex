defmodule Videdal.InternalNotes.Policy do
  use Hawk.Policy

  @moduledoc false

  read do
    role(:system, :all)
  end

  write(:never)
end
