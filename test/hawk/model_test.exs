defmodule Hawk.ModelTest do
  use ExUnit.Case, async: true

  test "models infer association policies and readers by resource convention" do
    assert Videdal.Course.__schema__(:association, :grades).related == Videdal.Grade
    assert Videdal.Course.__hawk_association_policy__(:grades) == {:ok, Videdal.Grades.Policy}
    assert Videdal.Grade.__hawk_association_policy__(:student) == {:ok, Videdal.Students.Policy}
    assert Videdal.Grade.__hawk_association_policy__(:course) == {:ok, Videdal.Courses.Policy}
    assert Videdal.Course.__hawk_association_reader__(:grades) == {:ok, Videdal.Grades.Reader}
    assert Videdal.Grade.__hawk_association_reader__(:student) == {:ok, Videdal.Students.Reader}
  end

  test "models allow explicit association policy and reader overrides" do
    assert Videdal.Student.__hawk_association_policy__(:parent_students) ==
             {:ok, Videdal.Parents.Policy}

    assert Videdal.Student.__hawk_association_reader__(:parent_students) ==
             {:ok, Videdal.Parents.Reader}
  end

  test "unknown association metadata fails closed" do
    assert Videdal.Course.__hawk_association_policy__(:missing) == :error
    assert Videdal.Course.__hawk_association_reader__(:missing) == :error
  end
end
