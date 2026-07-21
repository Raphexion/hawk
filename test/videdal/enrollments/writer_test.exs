defmodule Videdal.Enrollments.WriterTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Videdal.Enrollment
  alias Videdal.Enrollments

  @school_id Videdal.school_id()
  @student_id Videdal.student_id()
  @course_id Videdal.course_id()
  @other_course_id Videdal.other_course_id()
  @enrollment_id Videdal.enrollment_id()

  test "create runs through the resource writer pipeline" do
    authority =
      Authority.new(:school_admin, Videdal.school_admin_id(), scopes: %{school_id: @school_id})

    assert {:ok, %Enrollment{school_id: @school_id, student_id: @student_id, course_id: @course_id}} =
             Enrollments.create(
               %{school_id: @school_id, student_id: @student_id, course_id: @course_id},
               authority
             )
  end

  test "create accepts optional enrolled date" do
    authority =
      Authority.new(:school_admin, Videdal.school_admin_id(), scopes: %{school_id: @school_id})

    assert {:ok, %Enrollment{enrolled_on: ~D[2026-01-01]}} =
             Enrollments.create(
               %{
                 school_id: @school_id,
                 student_id: @student_id,
                 course_id: @course_id,
                 enrolled_on: ~D[2026-01-01]
               },
               authority
             )
  end

  test "update changes enrollment fields through the repository boundary" do
    enrollment = %Enrollment{
      id: @enrollment_id,
      school_id: @school_id,
      student_id: @student_id,
      course_id: @course_id
    }

    authority =
      Authority.new(:school_admin, Videdal.school_admin_id(), scopes: %{school_id: @school_id})

    assert {:ok,
            %Enrollment{
              id: @enrollment_id,
              course_id: @other_course_id,
              enrolled_on: ~D[2026-01-01]
            }} =
             Enrollments.update(
               enrollment,
               %{course_id: @other_course_id, enrolled_on: ~D[2026-01-01]},
               authority
             )

    assert_received {:videdal_repo, :transaction}
    assert_received {:videdal_repo, :update, changeset}
    assert changeset.changes == %{course_id: @other_course_id, enrolled_on: ~D[2026-01-01]}
  end

  test "delete rejects unauthorized authorities before persistence" do
    enrollment = %Enrollment{
      id: @enrollment_id,
      school_id: @school_id,
      student_id: @student_id,
      course_id: @course_id
    }

    authority =
      Authority.new(:student, @student_id, scopes: %{school_id: @school_id, student_id: @student_id})

    assert {:not_authorized, _context} = Enrollments.delete(enrollment, authority)
    refute_received {:videdal_repo, :delete, _enrollment}
  end
end
