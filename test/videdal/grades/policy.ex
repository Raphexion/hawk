defmodule Videdal.Grades.Policy do
  use Hawk.Policy

  import Ecto.Query

  @moduledoc """
  Authorization policy for the Videdal `Grades` resource.

  Grades intentionally pressure-test Hawk read policy because visibility crosses
  several relationship paths: teachers through courses, students directly, and
  parents through the parent/student link table.
  """

  read do
    role(:system, :all)
    role(:principal, :all)
    role(:school_admin, scopes: [:school_id])
    role(:teacher, scopes: [:school_id, :teacher_id])
    role(:student, scopes: [:school_id, :student_id])
    role(:parent, scopes: [:school_id, :parent_id])
  end

  write(roles: [:principal, :school_admin, :teacher])

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
