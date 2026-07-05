defmodule Hawk.ModelTest do
  use ExUnit.Case, async: true

  test "models expose association policies and readers next to schema metadata" do
    assert Videdal.Course.__schema__(:association, :grades).related == Videdal.Grade
    assert Videdal.Course.__hawk_association_policy__(:grades) == {:ok, Videdal.Grades.Policy}
    assert Videdal.Grade.__hawk_association_policy__(:student) == {:ok, Videdal.Students.Policy}
    assert Videdal.Grade.__hawk_association_policy__(:course) == {:ok, Videdal.Courses.Policy}
    assert Videdal.Course.__hawk_association_reader__(:grades) == {:ok, Videdal.Grades.Reader}
    assert Videdal.Grade.__hawk_association_reader__(:student) == {:ok, Videdal.Students.Reader}
  end

  test "unknown association metadata fails closed" do
    assert Videdal.Course.__hawk_association_policy__(:missing) == :error
    assert Videdal.Course.__hawk_association_reader__(:missing) == :error
  end
end
