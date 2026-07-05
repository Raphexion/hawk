defmodule Videdal.Students.Policy do
  use Hawk.Policy

  @moduledoc """
  Authorization policy for the Videdal `Students` resource.

  Read policy returns Hawk filter ASTs. Write policy receives a prepared
  mutation context and returns a boolean.
  """

  read do
    role(:system, :all)
    role(:principal, :all)
    role(:school_admin, scopes: [:school_id])
    role(:teacher, scopes: [:school_id])
    role(:student, scopes: [:school_id, :student_id], filter: %{active: true})
    role(:parent, scopes: [:school_id, :parent_id], filter: %{active: true})
  end

  write(roles: [:principal, :school_admin])
end
