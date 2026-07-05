defmodule Videdal.Enrollments.Policy do
  use Hawk.Policy

  @moduledoc """
  Authorization policy for the Videdal `Enrollments` resource.
  """

  read do
    role(:system, :all)
    role(:principal, :all)
    role(:school_admin, scopes: [:school_id])
    role(:teacher, scopes: [:school_id])
    role(:student, scopes: [:school_id, :student_id])
  end

  write(roles: [:principal, :school_admin])
end
