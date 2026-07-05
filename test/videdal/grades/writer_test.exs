defmodule Videdal.Grades.WriterTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Videdal.{Grade, Grades}

  test "teachers can create grades for their school" do
    authority = Authority.new(:teacher, 12, scopes: %{school_id: 7, teacher_id: 12})

    assert {:ok, %Grade{score: 12, school_id: 7, student_id: 8, course_id: 3}} =
             Grades.create(%{score: 12, school_id: 7, student_id: 8, course_id: 3}, authority)
  end

  test "students can read but cannot create grades" do
    authority = Authority.new(:student, 8, scopes: %{school_id: 7, student_id: 8})

    assert {:not_authorized, context} =
             Grades.create(%{score: 12, school_id: 7, student_id: 8, course_id: 3}, authority)

    assert context.policy_validated?
    refute_received {:videdal_repo, :insert, _changeset}
  end

  test "readonly teachers cannot create grades" do
    authority =
      :teacher
      |> Authority.new(12, scopes: %{school_id: 7, teacher_id: 12})
      |> Authority.readonly()

    assert {:not_authorized, _context} =
             Grades.create(%{score: 12, school_id: 7, student_id: 8, course_id: 3}, authority)

    refute_received {:videdal_repo, :insert, _changeset}
  end

  test "create rejects missing required fields before persistence" do
    authority = Authority.new(:teacher, 12, scopes: %{school_id: 7, teacher_id: 12})

    assert {:invalid, context} =
             Grades.create(%{score: 12, school_id: 7, student_id: 8}, authority)

    assert context.changeset.errors[:course_id]
    refute_received {:videdal_repo, :insert, _changeset}
  end

  test "teachers can update grades" do
    grade = %Grade{id: 1, score: 10, school_id: 7, student_id: 8, course_id: 3}
    authority = Authority.new(:teacher, 12, scopes: %{school_id: 7, teacher_id: 12})

    assert {:ok, %Grade{id: 1, score: 12}} = Grades.update(grade, %{score: 12}, authority)

    assert_received {:videdal_repo, :update, changeset}
    assert changeset.changes == %{score: 12}
  end

  test "students cannot update their own grades" do
    grade = %Grade{id: 1, score: 10, school_id: 7, student_id: 8, course_id: 3}
    authority = Authority.new(:student, 8, scopes: %{school_id: 7, student_id: 8})

    assert {:not_authorized, _context} = Grades.update(grade, %{score: 12}, authority)
    refute_received {:videdal_repo, :update, _changeset}
  end

  test "students cannot delete grades" do
    grade = %Grade{id: 1, score: 10, school_id: 7, student_id: 8, course_id: 3}
    authority = Authority.new(:student, 8, scopes: %{school_id: 7, student_id: 8})

    assert {:not_authorized, _context} = Grades.delete(grade, authority)
    refute_received {:videdal_repo, :delete, _grade}
  end
end
