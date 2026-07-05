defmodule Videdal.Grades.Policy do
  use Hawk.Policy

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
end
