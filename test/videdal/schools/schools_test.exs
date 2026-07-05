defmodule Videdal.SchoolsTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Videdal.{School, Schools}

  test "facade delegates reader functions" do
    school = %School{id: 7, name: "Videdal Skole"}
    Process.put({Videdal.Repo, :all_results}, [school])

    assert Schools.all(authority: Authority.system()) == [school]
    assert Schools.one(authority: Authority.system(), filter: %{id: 7}) == {:ok, school}
    assert Schools.one!(authority: Authority.system(), filter: %{id: 7}) == school
  end
end
