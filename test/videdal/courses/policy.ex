defmodule Videdal.Courses.Policy do
  @moduledoc """
  Authorization policy for the Videdal `Courses` resource.
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
        PolicySupport.scoped_filter(authority, [:school_id])

      true ->
        :none
    end
  end

  def create?(%MutationContext{} = context), do: course_admin?(context.authority)
  def update?(%MutationContext{} = context), do: course_admin?(context.authority)
  def delete?(%MutationContext{} = context), do: course_admin?(context.authority)

  defp course_admin?(%Authority{} = authority) do
    PolicySupport.write_allowed?(authority, [:principal, :school_admin])
  end
end
