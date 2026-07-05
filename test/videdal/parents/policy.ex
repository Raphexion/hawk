defmodule Videdal.Parents.Policy do
  use Hawk.Policy

  @moduledoc """
  Authorization policy for the Videdal `Parents` resource.
  """

  read do
    role(:system, :all)
    role(:principal, :all)
    role(:school_admin, scopes: [:school_id])
    role(:parent, scopes: [:school_id, :parent_id])
  end
end
