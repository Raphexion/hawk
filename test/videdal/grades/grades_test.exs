defmodule Videdal.GradesTest do
  use Videdal.DatabaseCase, async: true

  alias Hawk.Authority
  alias Videdal.Grades

  test "facade delegates one/1 to the reader" do
    grade = insert(:grade)

    assert {:ok, found} = Grades.one(authority: Authority.system(), filter: %{id: grade.id})
    assert found.id == grade.id
  end

  test "facade delegates all/1 to the reader" do
    grade = insert(:grade)

    [result] = Grades.all(authority: Authority.system())
    assert result.id == grade.id
  end
end
