defmodule Videdal.Grades.WriterTest do
  use Videdal.DatabaseCase, async: true

  alias Hawk.Authority
  alias Videdal.{Grade, Grades}

  test "teachers can create grades for their school" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)
    student = insert(:student, school_id: school.id)
    course = insert(:course, school_id: school.id, teacher_id: teacher.id)

    authority =
      Authority.new(:teacher, teacher.id, scopes: %{school_id: school.id, teacher_id: teacher.id})

    assert {:ok, %Grade{score: 12} = grade} =
             Grades.create(
               %{
                 score: 12,
                 school_id: school.id,
                 student_id: student.id,
                 course_id: course.id
               },
               authority
             )

    assert grade.school_id == school.id
  end

  test "students can read but cannot create grades" do
    school = insert(:school)
    student = insert(:student, school_id: school.id)

    authority =
      Authority.new(:student, student.id, scopes: %{school_id: school.id, student_id: student.id})

    assert {:not_authorized, context} =
             Grades.create(
               %{
                 score: 12,
                 school_id: school.id,
                 student_id: student.id,
                 course_id: insert(:course, school_id: school.id).id
               },
               authority
             )

    assert context.policy_validated?
  end

  test "readonly teachers cannot create grades" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)

    authority =
      :teacher
      |> Authority.new(teacher.id, scopes: %{school_id: school.id, teacher_id: teacher.id})
      |> Authority.readonly()

    assert {:not_authorized, _context} =
             Grades.create(
               %{
                 score: 12,
                 school_id: school.id,
                 student_id: insert(:student, school_id: school.id).id,
                 course_id: insert(:course, school_id: school.id, teacher_id: teacher.id).id
               },
               authority
             )
  end

  test "create rejects missing required fields before persistence" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)

    authority =
      Authority.new(:teacher, teacher.id, scopes: %{school_id: school.id, teacher_id: teacher.id})

    assert {:invalid, context} =
             Grades.create(
               %{score: 12, school_id: school.id, student_id: insert(:student, school_id: school.id).id},
               authority
             )

    assert context.changeset.errors[:course_id]
  end

  test "teachers can update grades" do
    grade = insert(:grade, score: 10)
    course = Videdal.Repo.get!(Videdal.Course, grade.course_id)
    teacher = Videdal.Repo.get!(Videdal.Teacher, course.teacher_id)
    authority = Authority.new(:teacher, teacher.id, scopes: %{school_id: grade.school_id, teacher_id: teacher.id})

    assert {:ok, %Grade{score: 12} = updated} = Grades.update(grade, %{score: 12}, authority)
    assert updated.id == grade.id
  end

  test "students cannot update their own grades" do
    grade = insert(:grade, score: 10)

    authority =
      Authority.new(:student, grade.student_id, scopes: %{school_id: grade.school_id, student_id: grade.student_id})

    assert {:not_authorized, _context} = Grades.update(grade, %{score: 12}, authority)
  end

  test "students cannot delete grades" do
    grade = insert(:grade, score: 10)

    authority =
      Authority.new(:student, grade.student_id, scopes: %{school_id: grade.school_id, student_id: grade.student_id})

    assert {:not_authorized, _context} = Grades.delete(grade, authority)
  end
end
