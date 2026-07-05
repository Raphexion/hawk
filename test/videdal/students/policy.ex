defmodule Videdal.Students.Policy do
  import Ecto.Query

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
        PolicySupport.scoped_filter(authority, [:school_id])

      authority.role == :student ->
        PolicySupport.scoped_filter(authority, [:school_id, :student_id], %{active: true})

      authority.role == :parent ->
        PolicySupport.scoped_filter(authority, [:school_id, :parent_id], %{active: true})

      true ->
        :none
    end
  end

  def preload_query(query, %Authority{role: :parent} = authority) do
    case read_filter(authority) do
      %{school_id: school_id, parent_id: parent_id, active: active} ->
        query
        |> join(:inner, [root: student], parent_student in assoc(student, :parent_students),
          as: :parent_student
        )
        |> where([root: student, parent_student: parent_student], student.school_id == ^school_id)
        |> where([root: student, parent_student: parent_student], student.active == ^active)
        |> where(
          [root: _student, parent_student: parent_student],
          parent_student.parent_id == ^parent_id
        )

      :none ->
        where(query, false)
    end
  end

  def preload_query(query, authority) do
    Hawk.Reader.FilterCompiler.compile(query, Videdal.Student, read_filter(authority), %{})
  end

  def create?(%MutationContext{} = context), do: write_allowed?(context.authority)
  def update?(%MutationContext{} = context), do: write_allowed?(context.authority)
  def delete?(%MutationContext{} = context), do: write_allowed?(context.authority)

  defp write_allowed?(%Authority{} = authority) do
    PolicySupport.write_allowed?(authority, [:principal, :school_admin])
  end
end
