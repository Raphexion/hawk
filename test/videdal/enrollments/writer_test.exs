defmodule Videdal.Enrollments.WriterTest do
  use Videdal.DatabaseCase, async: true

  alias Hawk.Authority
  alias Videdal.{Enrollment, Enrollments}

  test "create runs through the resource writer pipeline" do
    school = insert(:school)
    student = insert(:student, school_id: school.id)
    course = insert(:course, school_id: school.id)
    authority = Authority.new(:school_admin, 1, scopes: %{school_id: school.id})

    assert {:ok, %Enrollment{} = enrollment} =
             Enrollments.create(
               %{school_id: school.id, student_id: student.id, course_id: course.id},
               authority
             )

    assert enrollment.school_id == school.id
    assert enrollment.student_id == student.id
    assert enrollment.course_id == course.id
  end

  test "create accepts optional enrolled date" do
    school = insert(:school)
    student = insert(:student, school_id: school.id)
    course = insert(:course, school_id: school.id)
    authority = Authority.new(:school_admin, 1, scopes: %{school_id: school.id})

    assert {:ok, %Enrollment{enrolled_on: ~D[2026-01-01]}} =
             Enrollments.create(
               %{school_id: school.id, student_id: student.id, course_id: course.id, enrolled_on: ~D[2026-01-01]},
               authority
             )
  end

  test "update changes enrollment fields through the repository boundary" do
    school = insert(:school)
    enrollment = insert(:enrollment, school_id: school.id)
    other_course = insert(:course, school_id: school.id)
    authority = Authority.new(:school_admin, 1, scopes: %{school_id: school.id})

    assert {:ok, %Enrollment{} = updated} =
             Enrollments.update(enrollment, %{course_id: other_course.id, enrolled_on: ~D[2026-01-01]}, authority)

    assert updated.course_id == other_course.id
    assert updated.enrolled_on == ~D[2026-01-01]
  end

  test "delete rejects unauthorized authorities before persistence" do
    school = insert(:school)
    student = insert(:student, school_id: school.id)
    enrollment = insert(:enrollment, school_id: school.id, student_id: student.id)
    authority = Authority.new(:student, student.id, scopes: %{school_id: school.id, student_id: student.id})

    assert {:not_authorized, _context} = Enrollments.delete(enrollment, authority)
  end
end
