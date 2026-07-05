defmodule Videdal.Grades.Policy do
  import Ecto.Query

  @moduledoc """
  Authorization policy for the Videdal `Grades` resource.

  Grades intentionally pressure-test Hawk read policy because visibility crosses
  several relationship paths: teachers through courses, students directly, and
  parents through the parent/student link table.
  """

  alias Hawk.Authority
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
        PolicySupport.scoped_filter(authority, [:school_id, :student_id])

      authority.role == :parent ->
        PolicySupport.scoped_filter(authority, [:school_id, :parent_id])

      true ->
        :none
    end
  end

  def preload_query(query, authority) do
    case read_filter(authority) do
      :all ->
        query

      :none ->
        where(query, false)

      %{school_id: school_id, teacher_id: teacher_id} ->
        query
        |> join(:inner, [root: grade], course in assoc(grade, :course), as: :course)
        |> where([root: grade, course: course], grade.school_id == ^school_id)
        |> where([root: _grade, course: course], course.teacher_id == ^teacher_id)

      %{school_id: school_id, student_id: student_id} ->
        query
        |> where([root: grade], grade.school_id == ^school_id)
        |> where([root: grade], grade.student_id == ^student_id)

      %{school_id: school_id, parent_id: parent_id} ->
        query
        |> join(:inner, [root: grade], student in assoc(grade, :student), as: :student)
        |> join(:inner, [student: student], parent_student in assoc(student, :parent_students),
          as: :parent_student
        )
        |> where([root: grade], grade.school_id == ^school_id)
        |> where(
          [root: _grade, parent_student: parent_student],
          parent_student.parent_id == ^parent_id
        )

      %{school_id: school_id} ->
        where(query, [root: grade], grade.school_id == ^school_id)
    end
  end
end
