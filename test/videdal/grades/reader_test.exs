defmodule Videdal.Grades.ReaderTest do
  use Videdal.DatabaseCase, async: true

  import Ecto.Query

  alias Hawk.Authority
  alias Videdal.{Grades, Grades.Reader}

  test "declares relationship-heavy filters and policy-backed preloads" do
    assert Reader.filter_keys() ==
             MapSet.new([
               :id,
               :school_id,
               :student_id,
               :course_id,
               :score,
               :score_range,
               :student_name,
               :parent_id,
               :course_title,
               :teacher_id
             ])

    assert Reader.filter_value_types() == %{score_range: :object}
    assert Reader.preload_keys() == MapSet.new([:student, :course])

    assert Reader.preload_readers() == %{}
  end

  test "teacher policy filters trigger the explicit course join" do
    authority = Authority.new(:teacher, 12, scopes: %{school_id: 7, teacher_id: 12})
    query = Reader.preload_query(from(Videdal.Grade, as: :root), authority)

    inspected = inspect(query)
    assert inspected =~ "join: c1 in assoc(g0, :course)"
    assert inspected =~ "g0.school_id == ^7"
    assert inspected =~ "c1.teacher_id == ^12"
  end

  test "parent policy filters trigger student and parent link joins" do
    authority = Authority.new(:parent, 4, scopes: %{school_id: 7, parent_id: 4})
    query = Reader.preload_query(from(Videdal.Grade, as: :root), authority)

    inspected = inspect(query)
    assert inspected =~ "join: s1 in assoc(g0, :student)"
    assert inspected =~ "join: p2 in assoc(s1, :parent_students)"
    assert inspected =~ "g0.school_id == ^7"
    assert inspected =~ "p2.parent_id == ^4"
  end

  test "student policy conflicts with another student filter and returns no rows" do
    school = insert(:school)
    student = insert(:student, school_id: school.id)
    insert(:grade, school_id: school.id, student_id: student.id)

    authority = Authority.new(:student, student.id, scopes: %{school_id: school.id, student_id: student.id})
    other_student = insert(:student, school_id: school.id)

    assert Grades.all(authority: authority, filter: %{student_id: other_student.id}) == []
  end
end
