defmodule Videdal.Teachers.WriterTest do
  use Videdal.DatabaseCase, async: true

  alias Hawk.Authority
  alias Videdal.{Teacher, Teachers}

  test "create runs through the resource writer pipeline" do
    school = insert(:school)
    authority = Authority.new(:school_admin, 1, scopes: %{school_id: school.id})

    assert {:ok, %Teacher{name: "Grace"} = teacher} =
             Teachers.create(%{name: "Grace", school_id: school.id}, authority)

    assert teacher.school_id == school.id
  end

  test "create rejects readonly authorities" do
    school = insert(:school)

    authority =
      :school_admin
      |> Authority.new(1, scopes: %{school_id: school.id})
      |> Authority.readonly()

    assert {:not_authorized, _context} =
             Teachers.create(%{name: "Grace", school_id: school.id}, authority)
  end

  test "update changes permitted fields through the repository boundary" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id, name: "Grace")
    authority = Authority.new(:school_admin, 1, scopes: %{school_id: school.id})

    assert {:ok, %Teacher{name: "Grace Hopper"} = updated} =
             Teachers.update(teacher, %{name: "Grace Hopper", ignored: true}, authority)

    assert updated.id == teacher.id
  end

  test "delete rejects readonly authorities before persistence" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)

    authority =
      :school_admin
      |> Authority.new(1, scopes: %{school_id: school.id})
      |> Authority.readonly()

    assert {:not_authorized, _context} = Teachers.delete(teacher, authority)
  end
end
