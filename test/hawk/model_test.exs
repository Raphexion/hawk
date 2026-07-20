defmodule Hawk.ModelTest do
  use ExUnit.Case, async: true

  alias Hawk.ModelTest.DefaultUuidChild
  alias Hawk.ModelTest.DefaultUuidParent

  defmodule DefaultUuidParent do
    use Hawk.Model

    model "default_uuid_parents" do
      field(:name, :string)
    end
  end

  defmodule DefaultUuidChild do
    use Hawk.Model

    model "default_uuid_children" do
      field(:name, :string)
      belongs_to(:parent, DefaultUuidParent)
    end
  end

  test "models infer association policies and readers by resource convention" do
    assert Videdal.Course.__schema__(:association, :grades).related == Videdal.Grade
    assert Videdal.Course.__hawk_association_policy__(:grades) == {:ok, Videdal.Grades.Policy}
    assert Videdal.Grade.__hawk_association_policy__(:student) == {:ok, Videdal.Students.Policy}
    assert Videdal.Grade.__hawk_association_policy__(:course) == {:ok, Videdal.Courses.Policy}
    assert Videdal.Course.__hawk_association_reader__(:grades) == {:ok, Videdal.Grades.Reader}
    assert Videdal.Grade.__hawk_association_reader__(:student) == {:ok, Videdal.Students.Reader}
  end

  test "models allow explicit association policy and reader overrides" do
    assert Videdal.Student.__hawk_association_policy__(:parents) ==
             {:ok, Videdal.Parents.Policy}

    assert Videdal.Student.__hawk_association_reader__(:parents) ==
             {:ok, Videdal.Parents.Reader}
  end

  test "unknown association metadata fails closed" do
    assert Videdal.Course.__hawk_association_policy__(:missing) == :error
    assert Videdal.Course.__hawk_association_reader__(:missing) == :error
  end

  test "models default to UUID primary keys and foreign keys" do
    assert DefaultUuidParent.__schema__(:type, :id) == :binary_id
    assert DefaultUuidChild.__schema__(:type, :parent_id) == :binary_id
  end
end
