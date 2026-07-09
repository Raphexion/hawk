defmodule Videdal.Grades.WriterTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Videdal.{Grade, Grades}

  @school_id Videdal.school_id()
  @student_id Videdal.student_id()
  @teacher_id Videdal.teacher_id()
  @course_id Videdal.course_id()
  @grade_id Videdal.grade_id()

  test "teachers can create grades for their school" do
    authority =
      Authority.new(:teacher, @teacher_id,
        scopes: %{school_id: @school_id, teacher_id: @teacher_id}
      )

    assert {:ok,
            %Grade{
              score: 12,
              school_id: @school_id,
              student_id: @student_id,
              course_id: @course_id
            }} =
             Grades.create(
               %{
                 score: 12,
                 school_id: @school_id,
                 student_id: @student_id,
                 course_id: @course_id
               },
               authority
             )
  end

  test "students can read but cannot create grades" do
    authority =
      Authority.new(:student, @student_id,
        scopes: %{school_id: @school_id, student_id: @student_id}
      )

    assert {:not_authorized, context} =
             Grades.create(
               %{
                 score: 12,
                 school_id: @school_id,
                 student_id: @student_id,
                 course_id: @course_id
               },
               authority
             )

    assert context.policy_validated?
    refute_received {:videdal_repo, :insert, _changeset}
  end

  test "readonly teachers cannot create grades" do
    authority =
      :teacher
      |> Authority.new(@teacher_id, scopes: %{school_id: @school_id, teacher_id: @teacher_id})
      |> Authority.readonly()

    assert {:not_authorized, _context} =
             Grades.create(
               %{
                 score: 12,
                 school_id: @school_id,
                 student_id: @student_id,
                 course_id: @course_id
               },
               authority
             )

    refute_received {:videdal_repo, :insert, _changeset}
  end

  test "create rejects missing required fields before persistence" do
    authority =
      Authority.new(:teacher, @teacher_id,
        scopes: %{school_id: @school_id, teacher_id: @teacher_id}
      )

    assert {:invalid, context} =
             Grades.create(
               %{score: 12, school_id: @school_id, student_id: @student_id},
               authority
             )

    assert context.changeset.errors[:course_id]
    refute_received {:videdal_repo, :insert, _changeset}
  end

  test "teachers can update grades" do
    grade = %Grade{
      id: @grade_id,
      score: 10,
      school_id: @school_id,
      student_id: @student_id,
      course_id: @course_id
    }

    authority =
      Authority.new(:teacher, @teacher_id,
        scopes: %{school_id: @school_id, teacher_id: @teacher_id}
      )

    assert {:ok, %Grade{id: @grade_id, score: 12}} = Grades.update(grade, %{score: 12}, authority)

    assert_received {:videdal_repo, :update, changeset}
    assert changeset.changes == %{score: 12}
  end

  test "students cannot update their own grades" do
    grade = %Grade{
      id: @grade_id,
      score: 10,
      school_id: @school_id,
      student_id: @student_id,
      course_id: @course_id
    }

    authority =
      Authority.new(:student, @student_id,
        scopes: %{school_id: @school_id, student_id: @student_id}
      )

    assert {:not_authorized, _context} = Grades.update(grade, %{score: 12}, authority)
    refute_received {:videdal_repo, :update, _changeset}
  end

  test "students cannot delete grades" do
    grade = %Grade{
      id: @grade_id,
      score: 10,
      school_id: @school_id,
      student_id: @student_id,
      course_id: @course_id
    }

    authority =
      Authority.new(:student, @student_id,
        scopes: %{school_id: @school_id, student_id: @student_id}
      )

    assert {:not_authorized, _context} = Grades.delete(grade, authority)
    refute_received {:videdal_repo, :delete, _grade}
  end
end
