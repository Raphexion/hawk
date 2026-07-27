defmodule Mix.Tasks.Hawk.Plans.SpecTest do
  use ExUnit.Case, async: false

  setup do
    previous_shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)

    tmp = Path.join(System.tmp_dir!(), "hawk-plans-spec-#{System.unique_integer([:positive])}")
    File.rm_rf!(tmp)
    File.mkdir_p!(tmp)

    on_exit(fn ->
      Mix.shell(previous_shell)
      File.rm_rf!(tmp)
    end)

    {:ok, tmp: tmp}
  end

  test "writes a resource-shaped plan spec for discovered Hawk resources", %{tmp: tmp} do
    output = Path.join(tmp, "plans.json")

    # Use explicit resources to avoid the Videdal.Courses/Videdal.ExternalCourses
    # type collision (both declare type("courses")); discovery would overwrite.
    Mix.Tasks.Hawk.Plans.Spec.run(["Videdal.Courses", "Videdal.Teachers", "-o", output])

    spec = Jason.decode!(File.read!(output))

    assert Map.has_key?(spec["resources"], "courses")
    assert Map.has_key?(spec["resources"], "teachers")

    # The spec carries ops per resource, including actions for Courses.
    courses = spec["resources"]["courses"]
    ops = Enum.map(courses["ops"], & &1["op"])
    assert "read" in ops
    assert "create" in ops
    assert "action" in ops
  end

  test "explicit resources override discovery", %{tmp: tmp} do
    output = Path.join(tmp, "plans.json")

    Mix.Tasks.Hawk.Plans.Spec.run(["Videdal.Teachers", "-o", output])

    spec = Jason.decode!(File.read!(output))
    assert Map.has_key?(spec["resources"], "teachers")
    refute Map.has_key?(spec["resources"], "courses")
  end

  test "requires --output", _ctx do
    assert_raise ArgumentError, ~r/requires --output/, fn ->
      Mix.Tasks.Hawk.Plans.Spec.run([])
    end
  end
end
