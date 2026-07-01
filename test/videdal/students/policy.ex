defmodule Videdal.Students.Policy do
  @moduledoc """
  Authorization policy for the Videdal `Students` resource.

  Read policy returns Hawk filter ASTs. Write policy receives a prepared
  mutation context and returns a boolean.
  """

  alias Hawk.Authority
  alias Hawk.MutationContext
  alias Videdal.PolicySupport

  def read_filter(%Authority{} = authority) do
    cond do
      PolicySupport.unrestricted_read?(authority) ->
        :all

      authority.role == :school_admin ->
        PolicySupport.scoped_filter(authority, [:school_id])

      authority.role == :teacher ->
        PolicySupport.scoped_filter(authority, [:school_id, :teacher_id])

      authority.role == :student ->
        PolicySupport.scoped_filter(authority, [:school_id, :student_id], %{active: true})

      true ->
        :none
    end
  end

  def create?(%MutationContext{} = context), do: write_allowed?(context.authority)
  def update?(%MutationContext{} = context), do: write_allowed?(context.authority)
  def delete?(%MutationContext{} = context), do: write_allowed?(context.authority)

  defp write_allowed?(%Authority{} = authority) do
    PolicySupport.write_allowed?(authority, [:principal, :school_admin])
  end
end
