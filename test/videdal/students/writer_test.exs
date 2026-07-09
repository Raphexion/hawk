defmodule Videdal.Students.WriterTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Videdal.Student
  alias Videdal.Students

  @school_admin_id Videdal.school_admin_id()
  @school_id Videdal.school_id()
  @student_id Videdal.student_id()

  test "create runs through the resource writer pipeline" do
    authority = Authority.new(:school_admin, @school_admin_id, scopes: %{school_id: @school_id})

    assert {:ok, %Student{name: "Ada", school_id: @school_id, active: true}} =
             Students.create(%{name: "Ada", school_id: @school_id}, authority)
  end

  test "create rejects readonly authorities" do
    authority =
      :school_admin
      |> Authority.new(@school_admin_id, scopes: %{school_id: @school_id})
      |> Authority.readonly()

    assert {:not_authorized, _context} =
             Students.create(%{name: "Ada", school_id: @school_id}, authority)
  end

  test "update changes permitted fields and ignores unknown attrs" do
    student = %Student{id: @student_id, name: "Ada", school_id: @school_id, active: true}
    authority = Authority.new(:school_admin, @school_admin_id, scopes: %{school_id: @school_id})

    assert {:ok, %Student{id: @student_id, name: "Ada Lovelace", active: false}} =
             Students.update(
               student,
               %{name: "Ada Lovelace", active: false, ignored: true},
               authority
             )

    assert_received {:videdal_repo, :transaction}
    assert_received {:videdal_repo, :update, changeset}
    assert changeset.changes == %{name: "Ada Lovelace", active: false}
  end

  test "delete rejects readonly authorities before persistence" do
    student = %Student{id: @student_id, school_id: @school_id}

    authority =
      :school_admin
      |> Authority.new(@school_admin_id, scopes: %{school_id: @school_id})
      |> Authority.readonly()

    assert {:not_authorized, _context} = Students.delete(student, authority)
    refute_received {:videdal_repo, :delete, _student}
  end
end
