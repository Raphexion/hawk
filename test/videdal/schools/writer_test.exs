defmodule Videdal.Schools.WriterTest do
  use Videdal.DatabaseCase, async: true

  alias Hawk.Authority
  alias Videdal.{School, Schools}

  test "create runs through the resource writer pipeline" do
    assert {:ok, %School{name: "Videdal Skole"}} =
             Schools.create(%{name: "Videdal Skole"}, Authority.new(:principal, 1))
  end

  test "create rejects unauthorized authorities" do
    school = insert(:school)
    authority = Authority.new(:teacher, 1, scopes: %{school_id: school.id})

    assert {:not_authorized, _context} = Schools.create(%{name: "Videdal Skole"}, authority)
  end

  test "update changes permitted fields through the repository boundary" do
    school = insert(:school, name: "Old")

    assert {:ok, %School{name: "New"} = updated} =
             Schools.update(school, %{name: "New", ignored: true}, Authority.new(:principal, 1))

    assert updated.id == school.id
  end

  test "delete runs through the repository boundary" do
    school = insert(:school, name: "Videdal Skole")

    assert {:ok, deleted} = Schools.delete(school, Authority.new(:principal, 1))
    assert deleted.id == school.id
  end
end
