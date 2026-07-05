defmodule Videdal.Courses.WriterTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Videdal.Course
  alias Videdal.Courses

  test "create runs through the resource writer pipeline" do
    authority = Authority.new(:school_admin, 1, scopes: %{school_id: 7})

    assert {:ok, %Course{title: "Math", school_id: 7, teacher_id: 12}} =
             Courses.create(%{title: "Math", school_id: 7, teacher_id: 12}, authority)
  end

  test "create rejects missing required fields" do
    authority = Authority.new(:school_admin, 1, scopes: %{school_id: 7})

    assert {:invalid, context} = Courses.create(%{title: "Math", school_id: 7}, authority)
    assert context.changeset.errors[:teacher_id]
  end

  test "update changes title and relation ids through the repository boundary" do
    course = %Course{id: 3, title: "Math", school_id: 7, teacher_id: 12}
    authority = Authority.new(:school_admin, 1, scopes: %{school_id: 7})

    assert {:ok, %Course{id: 3, title: "Advanced Math", teacher_id: 13}} =
             Courses.update(course, %{title: "Advanced Math", teacher_id: 13}, authority)

    assert_received {:videdal_repo, :transaction}
    assert_received {:videdal_repo, :update, changeset}
    assert changeset.changes == %{title: "Advanced Math", teacher_id: 13}
  end

  test "delete rejects unauthorized authorities before persistence" do
    course = %Course{id: 3, school_id: 7, teacher_id: 12}
    authority = Authority.new(:teacher, 12, scopes: %{school_id: 7, teacher_id: 12})

    assert {:not_authorized, _context} = Courses.delete(course, authority)
    refute_received {:videdal_repo, :delete, _course}
  end
end
