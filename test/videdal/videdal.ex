defmodule Videdal do
  @moduledoc """
  Example application namespace used by Hawk's contract tests.

  Videdal models a small school application. Its resource folders intentionally
  follow `hawk_structure.md` so the tests double as study material for Hawk
  adopters.
  """

  def principal_id, do: "00000000-0000-0000-0000-000000000001"
  def school_admin_id, do: "00000000-0000-0000-0000-000000000002"
  def school_id, do: "00000000-0000-0000-0000-000000000007"
  def other_school_id, do: "00000000-0000-0000-0000-000000000009"
  def student_id, do: "00000000-0000-0000-0000-000000000008"
  def other_student_id, do: "00000000-0000-0000-0000-000000000010"
  def teacher_id, do: "00000000-0000-0000-0000-000000000012"
  def other_teacher_id, do: "00000000-0000-0000-0000-000000000013"
  def course_id, do: "00000000-0000-0000-0000-000000000003"
  def other_course_id, do: "00000000-0000-0000-0000-000000000004"
  def grade_id, do: "00000000-0000-0000-0000-000000000005"
  def enrollment_id, do: "00000000-0000-0000-0000-000000000006"
  def parent_id, do: "00000000-0000-0000-0000-000000000014"
  def other_parent_id, do: "00000000-0000-0000-0000-<PHONE_NUMBER_16>"
end
