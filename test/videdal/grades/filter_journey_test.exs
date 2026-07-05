defmodule Videdal.Grades.FilterJourneyTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Videdal.Grades

  test "grade reader composes relationship filters through declared joins" do
    Process.put({Videdal.Repo, :all_results}, [])

    assert Grades.all(
             authority: Authority.system(),
             filter: %{student_name: "Ada", course_title: "Math"}
           ) == []

    assert_received {:videdal_repo, :all, query}
    inspected = inspect(query)
    assert inspected =~ "join: s1 in assoc(g0, :student)"
    assert inspected =~ "join: c2 in assoc(g0, :course)"
    assert inspected =~ ~s(s1.name == ^"Ada")
    assert inspected =~ ~s(c2.title == ^"Math")
  end
end
