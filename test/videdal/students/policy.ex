defmodule Videdal.Students.Policy do
  use Hawk.Policy

  import Ecto.Query

  @moduledoc """
  Authorization policy for the Videdal `Students` resource.

  Read policy returns Hawk filter ASTs. Write policy receives a prepared
  mutation context and returns a boolean.
  """

  alias Hawk.Authority

  read do
    role(:system, :all)
    role(:principal, :all)
    role(:school_admin, scopes: [:school_id])
    role(:teacher, scopes: [:school_id])
    role(:student, scopes: [:school_id, :student_id], filter: %{active: true})
    role(:parent, scopes: [:school_id, :parent_id], filter: %{active: true})
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

  write(roles: [:principal, :school_admin])
end
