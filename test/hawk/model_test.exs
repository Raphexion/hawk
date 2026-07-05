defmodule Hawk.ModelTest do
  use ExUnit.Case, async: true

  test "models expose association policies next to schema metadata" do
    assert Videdal.Course.__schema__(:association, :grades).related == Videdal.Grade
    assert Videdal.Course.__hawk_association_policy__(:grades) == {:ok, Videdal.Grades.Policy}
    assert Videdal.Grade.__hawk_association_policy__(:student) == {:ok, Videdal.Students.Policy}
    assert Videdal.Grade.__hawk_association_policy__(:course) == {:ok, Videdal.Courses.Policy}
  end

  test "unknown association policies fail closed" do
    assert Videdal.Course.__hawk_association_policy__(:missing) == :error
  end
end
