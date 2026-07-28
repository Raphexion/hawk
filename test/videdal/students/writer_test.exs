defmodule Videdal.Students.WriterTest do
  use Videdal.DatabaseCase, async: true

  alias Hawk.Authority
  alias Videdal.{Student, Students}

  test "create runs through the resource writer pipeline" do
    school = insert(:school)
    authority = Authority.new(:school_admin, 1, scopes: %{school_id: school.id})

    assert {:ok, %Student{name: "Ada", active: true} = student} =
             Students.create(%{name: "Ada", school_id: school.id}, authority)

    assert student.school_id == school.id
  end

  test "create rejects readonly authorities" do
    school = insert(:school)
    authority =
      :school_admin
      |> Authority.new(1, scopes: %{school_id: school.id})
      |> Authority.readonly()

    assert {:not_authorized, _context} =
             Students.create(%{name: "Ada", school_id: school.id}, authority)
  end

  test "update changes permitted fields and ignores unknown attrs" do
    school = insert(:school)
    student = insert(:student, school_id: school.id, name: "Ada")
    authority = Authority.new(:school_admin, 1, scopes: %{school_id: school.id})

    assert {:ok, %Student{name: "Ada Lovelace", active: false} = updated} =
             Students.update(student, %{name: "Ada Lovelace", active: false, ignored: true}, authority)

    assert updated.id == student.id
  end

  test "delete rejects readonly authorities before persistence" do
    school = insert(:school)
    student = insert(:student, school_id: school.id)
    authority =
      :school_admin
      |> Authority.new(1, scopes: %{school_id: school.id})
      |> Authority.readonly()

    assert {:not_authorized, _context} = Students.delete(student, authority)
  end
end
