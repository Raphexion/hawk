defmodule Videdal.Courses.Policy do
  use Hawk.Policy

  @moduledoc """
  Authorization policy for the Videdal `Courses` resource.
  """

  read do
    role(:system, :all)
    role(:public, :all)
    role(:principal, :all)
    role(:school_admin, scopes: [:school_id])
    role(:teacher, scopes: [:school_id, :teacher_id])
    role(:student, scopes: [:school_id])
    role(:parent, scopes: [:school_id])
  end

  write(roles: [:principal, :school_admin])
end
