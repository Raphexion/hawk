defmodule Videdal.GradesTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Videdal.{Grade, Grades}

  test "facade delegates one/1 and one!/1 to the reader" do
    grade = %Grade{id: 1, school_id: 7, student_id: 8, course_id: 3, score: 12}
    Process.put({Videdal.Repo, :all_results}, [grade])

    assert Grades.one(authority: Authority.system(), filter: %{id: 1}) == {:ok, grade}
    assert Grades.one!(authority: Authority.system(), filter: %{id: 1}) == grade
  end

  test "facade delegates all/1 to the reader" do
    grades = [%Grade{id: 1, score: 12}]
    Process.put({Videdal.Repo, :all_results}, grades)

    assert Grades.all(authority: Authority.system()) == grades
  end
end
