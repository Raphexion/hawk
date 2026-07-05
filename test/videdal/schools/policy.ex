defmodule Videdal.Schools.Policy do
  use Hawk.Policy

  @moduledoc """
  Authorization policy for the Videdal `Schools` resource.
  """

  read do
    role(:system, :all)
    role(:principal, :all)
    role(:school_admin, scopes: [id: :school_id])
    role(:teacher, scopes: [id: :school_id])
    role(:student, scopes: [id: :school_id])
  end

  write(roles: [:principal])
end
