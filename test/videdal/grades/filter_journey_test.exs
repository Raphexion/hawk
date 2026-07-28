defmodule Videdal.Grades.FilterJourneyTest do
  use Videdal.DatabaseCase, async: true

  alias Hawk.Authority
  alias Videdal.Grades

  test "grade reader composes relationship filters through declared joins" do
    insert(:grade)

    results =
      Grades.all(
        authority: Authority.system(),
        filter: %{student_name: "Ada", course_title: "Math"}
      )

    assert results == []
  end
end
