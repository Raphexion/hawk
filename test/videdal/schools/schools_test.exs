defmodule Videdal.SchoolsTest do
  use Videdal.DatabaseCase, async: true

  alias Hawk.Authority
  alias Videdal.Schools

  test "facade delegates reader functions" do
    Videdal.Repo.delete_all(Videdal.School)
    school = insert(:school, name: "Videdal Skole")

    assert [result] = Schools.all(authority: Authority.system())
    assert result.id == school.id
    assert result.name == "Videdal Skole"

    assert {:ok, found} = Schools.one(authority: Authority.system(), filter: %{id: school.id})
    assert found.id == school.id
  end
end
