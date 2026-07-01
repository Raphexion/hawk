defmodule Videdal.Schools.Policy do
  @moduledoc """
  Authorization policy for the Videdal `Schools` resource.
  """

  alias Hawk.Authority
  alias Hawk.MutationContext
  alias Videdal.PolicySupport

  def read_filter(%Authority{} = authority) do
    cond do
      PolicySupport.unrestricted_read?(authority) ->
        :all

      authority.role in [:school_admin, :teacher, :student] ->
        PolicySupport.scoped_filter(authority, id: :school_id)

      true ->
        :none
    end
  end

  def create?(%MutationContext{} = context), do: principal_or_system?(context.authority)
  def update?(%MutationContext{} = context), do: principal_or_system?(context.authority)
  def delete?(%MutationContext{} = context), do: principal_or_system?(context.authority)

  defp principal_or_system?(%Authority{} = authority) do
    PolicySupport.write_allowed?(authority, [:principal])
  end
end
