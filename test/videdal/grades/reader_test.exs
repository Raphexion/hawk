defmodule Videdal.Grades.ReaderTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Videdal.Grades
  alias Videdal.Grades.Reader

  test "declares relationship-heavy filters and policy-backed preloads" do
    assert Reader.filter_keys() ==
             MapSet.new([
               :id,
               :school_id,
               :student_id,
               :course_id,
               :score,
               :student_name,
               :parent_id,
               :course_title,
               :teacher_id
             ])

    assert Reader.preload_keys() == MapSet.new([:student, :course])

    assert Reader.preload_policies() == %{}
  end

  test "teacher policy filters trigger the explicit course join" do
    authority = Authority.new(:teacher, 12, scopes: %{school_id: 7, teacher_id: 12})
    Process.put({Videdal.Repo, :all_results}, [])

    assert Grades.all(authority: authority) == []

    assert_received {:videdal_repo, :all, query}
    inspected = inspect(query)
    assert inspected =~ "join: c1 in assoc(g0, :course)"
    assert inspected =~ "g0.school_id == ^7"
    assert inspected =~ "c1.teacher_id == ^12"
  end

  test "parent policy filters trigger student and parent link joins" do
    authority = Authority.new(:parent, 4, scopes: %{school_id: 7, parent_id: 4})
    Process.put({Videdal.Repo, :all_results}, [])

    assert Grades.all(authority: authority) == []

    assert_received {:videdal_repo, :all, query}
    inspected = inspect(query)
    assert inspected =~ "join: s1 in assoc(g0, :student)"
    assert inspected =~ "join: p2 in assoc(s1, :parent_students)"
    assert inspected =~ "g0.school_id == ^7"
    assert inspected =~ "p2.parent_id == ^4"
  end

  test "student policy conflicts with another student filter and returns no rows" do
    authority = Authority.new(:student, 8, scopes: %{school_id: 7, student_id: 8})
    Process.put({Videdal.Repo, :all_results}, [])

    assert Grades.all(authority: authority, filter: %{student_id: 9}) == []

    assert_received {:videdal_repo, :all, query}
    assert inspect(query) =~ "where: false"
  end
end
