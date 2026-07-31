defmodule Hawk.LiveViewPathSourceTest do
  use ExUnit.Case, async: true

  import Hawk.LiveView, only: [field_value: 2, derive_preloads: 1, derive_preloads: 2]

  defp field(name, source), do: %{name: name, source: source}

  test "field_value resolves a scalar atom source" do
    assert field_value(%Videdal.Course{title: "Math"}, field(:title, :title)) == "Math"
  end

  test "field_value walks a path source through a preloaded association" do
    course = %Videdal.Course{
      teacher: %Videdal.Teacher{name: "Lena"},
      school: %Videdal.School{name: "Northbridge"}
    }

    assert field_value(course, field(:teacher_name, [:teacher, :name])) == "Lena"
    assert field_value(course, field(:school_name, [:school, :name])) == "Northbridge"
  end

  test "field_value returns nil when the association is not loaded" do
    course = %Videdal.Course{teacher: %Ecto.Association.NotLoaded{}}
    assert field_value(course, field(:teacher_name, [:teacher, :name])) == nil
  end

  test "field_value falls back to the field name when no source is declared" do
    assert field_value(%Videdal.Course{title: "Math"}, %{name: :title}) == "Math"
  end

  describe "derive_preloads/1" do
    test "collects top-level associations from one-level path sources" do
      fields = [
        %{name: :title},
        %{name: :teacher_name, source: [:teacher, :name]},
        %{name: :school_name, source: [:school, :name]}
      ]

      assert Enum.sort(derive_preloads(fields)) == [:school, :teacher]
    end

    test "builds nested preload specs for deeper path sources" do
      fields = [%{name: :teacher_name, source: [:course, :teacher, :name]}]

      assert derive_preloads(fields) == [course: [:teacher]]
    end

    test "merges paths that share a prefix" do
      fields = [
        %{name: :course_title, source: [:course, :title]},
        %{name: :teacher_name, source: [:course, :teacher, :name]}
      ]

      assert derive_preloads(fields) == [course: [:teacher]]
    end

    test "scalar fields contribute no preloads" do
      assert derive_preloads([%{name: :title}, %{name: :score}]) == []
    end

    test "model-aware variant keeps association-leaf paths for nested preloads" do
      fields = [%{name: :grades_student, source: [:grades, :student]}]

      assert derive_preloads(fields, Videdal.Course) == [grades: [:student]]
    end
  end
end
