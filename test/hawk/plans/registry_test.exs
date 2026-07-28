defmodule Hawk.Plans.RegistryTest do
  use ExUnit.Case, async: true

  alias Hawk.Plans.Registry

  describe "resolve/1" do
    test "resolves a known JSON:API type to its facade" do
      assert {:ok, Videdal.Courses} = Registry.resolve("courses")
      assert {:ok, Videdal.Teachers} = Registry.resolve("teachers")
      assert {:ok, Videdal.Enrollments} = Registry.resolve("enrollments")
    end

    test "returns :error for an unknown type" do
      assert :error = Registry.resolve("nonexistent")
      assert :error = Registry.resolve("")
    end
  end

  describe "registry/0" do
    test "returns a map keyed by JSON:API type" do
      reg = Registry.registry()

      assert is_map(reg)
      assert reg["courses"] == Videdal.Courses
      assert reg["teachers"] == Videdal.Teachers
    end

    test "omits resources with json_api disabled" do
      reg = Registry.registry()

      refute Map.has_key?(reg, "internal-notes")
      refute Map.has_key?(reg, "policy-checked-courses")
    end

    test "first-discovered wins on type collision" do
      reg = Registry.registry()

      # Both Videdal.Courses and Videdal.ExternalCourses declare type("courses").
      # Alphabetically, Videdal.Courses comes first, so it wins.
      assert reg["courses"] == Videdal.Courses
      refute reg["courses"] == Videdal.ExternalCourses
    end

    test "includes declared-identity resources" do
      reg = Registry.registry()

      assert reg["course-rosters"] == Videdal.CourseRosters
    end
  end
end
