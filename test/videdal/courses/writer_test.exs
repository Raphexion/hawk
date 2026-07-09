defmodule Videdal.Courses.WriterTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Videdal.Course
  alias Videdal.Courses

  @school_id Videdal.school_id()
  @teacher_id Videdal.teacher_id()
  @other_teacher_id Videdal.other_teacher_id()
  @course_id Videdal.course_id()

  test "create runs through the resource writer pipeline" do
    authority =
      Authority.new(:school_admin, Videdal.school_admin_id(), scopes: %{school_id: @school_id})

    assert {:ok, %Course{title: "Math", school_id: @school_id, teacher_id: @teacher_id}} =
             Courses.create(
               %{title: "Math", school_id: @school_id, teacher_id: @teacher_id},
               authority
             )
  end

  test "create rejects missing required fields" do
    authority =
      Authority.new(:school_admin, Videdal.school_admin_id(), scopes: %{school_id: @school_id})

    assert {:invalid, context} =
             Courses.create(%{title: "Math", school_id: @school_id}, authority)

    assert context.changeset.errors[:teacher_id]
  end

  test "update changes title and relation ids through the repository boundary" do
    course = %Course{
      id: @course_id,
      title: "Math",
      school_id: @school_id,
      teacher_id: @teacher_id
    }

    authority =
      Authority.new(:school_admin, Videdal.school_admin_id(), scopes: %{school_id: @school_id})

    assert {:ok, %Course{id: @course_id, title: "Advanced Math", teacher_id: @other_teacher_id}} =
             Courses.update(
               course,
               %{title: "Advanced Math", teacher_id: @other_teacher_id},
               authority
             )

    assert_received {:videdal_repo, :transaction}
    assert_received {:videdal_repo, :update, changeset}
    assert changeset.changes == %{title: "Advanced Math", teacher_id: @other_teacher_id}
  end

  test "delete rejects unauthorized authorities before persistence" do
    course = %Course{id: @course_id, school_id: @school_id, teacher_id: @teacher_id}

    authority =
      Authority.new(:teacher, @teacher_id,
        scopes: %{school_id: @school_id, teacher_id: @teacher_id}
      )

    assert {:not_authorized, _context} = Courses.delete(course, authority)
    refute_received {:videdal_repo, :delete, _course}
  end
end
