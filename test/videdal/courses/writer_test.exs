defmodule Videdal.Courses.WriterTest do
  use Videdal.DatabaseCase, async: true

  alias Hawk.Authority
  alias Videdal.{Course, Courses}

  test "create runs through the resource writer pipeline" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)
    authority = Authority.new(:school_admin, 1, scopes: %{school_id: school.id})

    assert {:ok, %Course{title: "Math"} = course} =
             Courses.create(%{title: "Math", school_id: school.id, teacher_id: teacher.id}, authority)

    assert course.school_id == school.id
    assert course.teacher_id == teacher.id
  end

  test "create rejects missing required fields" do
    school = insert(:school)
    authority = Authority.new(:school_admin, 1, scopes: %{school_id: school.id})

    assert {:invalid, context} =
             Courses.create(%{title: "Math", school_id: school.id}, authority)

    assert context.changeset.errors[:teacher_id]
  end

  test "update changes title and relation ids through the repository boundary" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)
    other_teacher = insert(:teacher, school_id: school.id)
    course = insert(:course, school_id: school.id, teacher_id: teacher.id)
    authority = Authority.new(:school_admin, 1, scopes: %{school_id: school.id})

    assert {:ok, %Course{title: "Advanced Math"} = updated} =
             Courses.update(course, %{title: "Advanced Math", teacher_id: other_teacher.id}, authority)

    assert updated.teacher_id == other_teacher.id
  end

  test "delete rejects unauthorized authorities before persistence" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)
    course = insert(:course, school_id: school.id, teacher_id: teacher.id)
    authority = Authority.new(:teacher, teacher.id, scopes: %{school_id: school.id, teacher_id: teacher.id})

    assert {:not_authorized, _context} = Courses.delete(course, authority)
  end
end
