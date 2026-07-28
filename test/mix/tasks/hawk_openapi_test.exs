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

  test "every operation has a unique, non-nil operationId", %{tmp: tmp} do
    output = Path.join(tmp, "openapi.json")

    Mix.Tasks.Hawk.Openapi.run(["-o", output, "--title", "Videdal API", "--version", "1.0.0"])

    spec = Jason.decode!(File.read!(output))

    operation_ids =
      for {_path, methods} <- spec["paths"],
          {_method, op} <- methods,
          is_map(op),
          not is_binary(op) do
        op["operationId"]
      end

    assert Enum.all?(operation_ids, &(&1 != nil)),
           "some operations are missing operationId: #{inspect(operation_ids)}"

    duplicates = operation_ids -- Enum.uniq(operation_ids)
    assert duplicates == [], "duplicate operationIds: #{inspect(duplicates)}"
  end

  test "standard operations follow the list/show/create/update/delete convention", %{tmp: tmp} do
    output = Path.join(tmp, "openapi.json")

    Mix.Tasks.Hawk.Openapi.run(["Videdal.Schools", "-o", output])

    spec = Jason.decode!(File.read!(output))

    assert spec["paths"]["/schools"]["get"]["operationId"] == "listSchools"
    assert spec["paths"]["/schools"]["post"]["operationId"] == "createSchools"
    assert spec["paths"]["/schools/{id}"]["get"]["operationId"] == "showSchools"
    assert spec["paths"]["/schools/{id}"]["patch"]["operationId"] == "updateSchools"
    assert spec["paths"]["/schools/{id}"]["delete"]["operationId"] == "deleteSchools"
  end

  test "relationship and related operations are distinguished in the operationId", %{tmp: tmp} do
    output = Path.join(tmp, "openapi.json")

    Mix.Tasks.Hawk.Openapi.run(["Videdal.Courses", "-o", output])

    spec = Jason.decode!(File.read!(output))

    assert spec["paths"]["/courses/{id}/relationships/{relationship}"]["get"]["operationId"] ==
             "showCoursesRelationship"
    assert spec["paths"]["/courses/{id}/{relationship}"]["get"]["operationId"] ==
             "showCoursesRelated"
  end

  test "action operations get a per-action operationId", %{tmp: tmp} do
    output = Path.join(tmp, "openapi.json")

    Mix.Tasks.Hawk.Openapi.run(["Videdal.Courses", "-o", output])

    spec = Jason.decode!(File.read!(output))

    assert spec["paths"]["/courses/{id}/-actions/open-registration"]["post"]["operationId"] ==
             "runCoursesOpenRegistration"
    assert spec["paths"]["/courses/{id}/-actions/close-registration"]["post"]["operationId"] ==
             "runCoursesCloseRegistration"
  end
end
