defmodule Videdal.Parents.Policy do
  @moduledoc """
  Authorization policy for the Videdal `Parents` resource.
  """

  alias Hawk.Authority
  alias Videdal.PolicySupport

  def read_filter(%Authority{} = authority) do
    cond do
      PolicySupport.unrestricted_read?(authority) ->
        :all

      authority.role == :school_admin ->
        PolicySupport.scoped_filter(authority, [:school_id])

      authority.role == :parent ->
        PolicySupport.scoped_filter(authority, [:school_id, :parent_id])

      true ->
        :none
    end
  end
end
