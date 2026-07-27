defmodule Mix.Tasks.Hawk.OpenapiTest do
  use ExUnit.Case, async: false

  setup do
    previous_shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)

    tmp = Path.join(System.tmp_dir!(), "hawk-openapi-#{System.unique_integer([:positive])}")
    File.rm_rf!(tmp)
    File.mkdir_p!(tmp)

    on_exit(fn ->
      Mix.shell(previous_shell)
      File.rm_rf!(tmp)
    end)

    {:ok, tmp: tmp}
  end

  test "discovers every Hawk facade and writes a real OpenAPI spec", %{tmp: tmp} do
    output = Path.join(tmp, "openapi.json")

    Mix.Tasks.Hawk.Openapi.run(["-o", output, "--title", "Videdal API", "--version", "1.0.0"])

    spec = Jason.decode!(File.read!(output))

    # Every facade with json_api enabled appears; the two json_api:false
    # resources (InternalNotes, PolicyCheckedCourses) are omitted.
    paths = Map.keys(spec["paths"]) |> Enum.sort()

    assert "/courses" in paths
    assert "/course-rosters" in paths
    assert "/course-grade-summaries" in paths
    refute Enum.any?(paths, &String.starts_with?(&1, "/internal-notes"))
    refute Enum.any?(paths, &String.starts_with?(&1, "/policy-checked-courses"))

    # The spec is non-empty and carries resource schemas.
    assert map_size(spec["paths"]) > 0
    assert Map.has_key?(spec["components"]["schemas"], "CourseResource")
    assert Map.has_key?(spec["components"]["schemas"], "CourseRosterResource")
    # ExternalCourses maps to type "courses" but keeps its own schema name.
    assert Map.has_key?(spec["components"]["schemas"], "ExternalCourseResource")
  end

  test "explicit resources override discovery", %{tmp: tmp} do
    output = Path.join(tmp, "openapi.json")

    Mix.Tasks.Hawk.Openapi.run(["Videdal.Courses", "-o", output])

    spec = Jason.decode!(File.read!(output))

    paths = Map.keys(spec["paths"]) |> Enum.sort()

    assert Enum.all?(paths, &String.starts_with?(&1, "/courses"))
    refute Map.has_key?(spec["paths"], "/schools")
    # Courses has actions enabled, so the action routes are present.
    assert Map.has_key?(spec["paths"], "/courses/{id}/-actions/open-registration")
  end

  test "requires --output", _ctx do
    assert_raise ArgumentError, ~r/requires --output/, fn ->
      Mix.Tasks.Hawk.Openapi.run(["--title", "x"])
    end
  end
end
