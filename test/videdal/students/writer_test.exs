defmodule Videdal.Students.WriterTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Videdal.Student
  alias Videdal.Students

  test "create runs through the resource writer pipeline" do
    authority = Authority.new(:school_admin, 1, scopes: %{school_id: 7})

    assert {:ok, %Student{name: "Ada", school_id: 7, active: true}} =
             Students.create(%{name: "Ada", school_id: 7}, authority)
  end

  test "create rejects readonly authorities" do
    authority =
      :school_admin
      |> Authority.new(1, scopes: %{school_id: 7})
      |> Authority.readonly()

    assert {:not_authorized, _context} =
             Students.create(%{name: "Ada", school_id: 7}, authority)
  end

  test "update changes permitted fields and ignores unknown attrs" do
    student = %Student{id: 8, name: "Ada", school_id: 7, active: true}
    authority = Authority.new(:school_admin, 1, scopes: %{school_id: 7})

    assert {:ok, %Student{id: 8, name: "Ada Lovelace", active: false}} =
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
    student = %Student{id: 8, school_id: 7}

    authority =
      :school_admin
      |> Authority.new(1, scopes: %{school_id: 7})
      |> Authority.readonly()

    assert {:not_authorized, _context} = Students.delete(student, authority)
    refute_received {:videdal_repo, :delete, _student}
  end
end
