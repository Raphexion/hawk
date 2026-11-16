defmodule Hawk.OpenApiQualityTest do
  use ExUnit.Case, async: true

  test "generic errors and includes do not leak a framework or example application's vocabulary" do
    spec = Hawk.OpenApi.spec([Videdal.Courses], title: "Test API")
    encoded = Jason.encode!(spec)
    refute encoded =~ "Forbidden by Hawk policy"
    refute encoded =~ "lessons.cards.blocks"

    for {_path, methods} <- spec.paths, {_method, operation} <- methods do
      expanded = expand(operation, spec)
      assert expanded.responses["400"].description == "Invalid JSON:API request (parameters or document)"
      assert expanded.responses["403"].description == "Forbidden by authorization policy"
      assert operation.description |> String.trim() != ""
    end
  end

  test "read IDs describe exactly the UUID and eight-hex-character alternatives" do
    spec = Hawk.OpenApi.spec([Videdal.Courses], title: "Test API")
    id = spec.paths["/courses/{id}"].get.parameters |> hd() |> expand(spec)
    pattern = Regex.compile!(id.schema.pattern)

    for value <- [Ecto.UUID.generate(), "Ab12Cd34"] do
      assert Regex.match?(pattern, value)
    end

    for value <- [
          "123",
          "abcdefgh",
          "123456789",
          "00000000-0000-0000-0000-00000000000x",
          "12345678\n",
          Ecto.UUID.generate() <> "\n"
        ] do
      refute Regex.match?(pattern, value)
    end

    assert (spec.paths["/courses/{id}"].patch.parameters |> hd() |> expand(spec)).schema.format == "uuid"
  end

  test "schema examples use JSON Schema examples arrays, preserving relationship data wrappers" do
    spec = Hawk.OpenApi.spec([Videdal.Courses], title: "Test API")
    resource = spec.components.schemas[:CourseResource]
    assert resource.properties.attributes.properties.title.examples == ["Math"]

    assert resource.properties.relationships.properties.school.examples == [
             %{data: %{type: "schools", id: Videdal.school_id()}}
           ]

    refute Map.has_key?(resource.properties.attributes.properties.title, :example)
  end

  test "resource tags have useful defaults and grouping remains host-controlled" do
    spec = Hawk.OpenApi.spec([Videdal.Courses], title: "Test API", presentation: Hawk.Test.OpenApiLimitedPresentation)
    assert spec.paths["/course-entries"].get.tags == ["course-entries"]
    assert Enum.any?(spec.tags, &(&1.name == "course-entries" and is_binary(&1.description)))
  end

  test "declared operation capability drives both routes and the specification" do
    adapter = Hawk.Test.OpenApiLimitedPresentation
    resource = %{resource: Videdal.Courses, json_api: adapter.__hawk_json_api__()}
    routes = Hawk.JsonApi.Routes.routes(resource)
    refute Enum.any?(routes, &(&1.action == :update))
    assert Enum.any?(routes, &(&1.action == :create))

    spec = Hawk.OpenApi.spec([Videdal.Courses], title: "Test API", presentation: adapter)
    refute Map.has_key?(spec.paths["/course-entries/{id}"], :patch)
    assert spec.paths["/course-entries"].post.summary == "Create course entry"
    assert spec.paths["/course-entries"].post.description == "A course entry in the Videdal catalog."
    assert spec.paths["/course-entries/{id}/-actions/open-registration"].post
  end

  test "summaries use singular model names, not naive trimming of external types" do
    spec = Hawk.OpenApi.spec([Videdal.CourseCatalog], title: "Test API")
    assert spec.paths["/course-catalog/{id}"].get.summary == "Show course"
  end

  test "host-owned info description and contact are optional" do
    spec =
      Hawk.OpenApi.spec([],
        title: "Test API",
        description: "A private authoring API",
        contact: %{name: "API support", url: "https://example.com/help"}
      )

    assert spec.info.description == "A private authoring API"
    assert spec.info.contact.name == "API support"
    refute Map.has_key?(Hawk.OpenApi.spec([], title: "Test API").info, :license)
  end

  test "shared components resolve to the same contract across operations" do
    opts = [title: "Test API", security: [%{"bearerAuth" => []}]]
    shared = Hawk.OpenApi.spec([Videdal.Courses], opts)
    inline = expand(shared, shared)
    assert shared.paths["/courses/{id}"].get.parameters |> hd() == %{"$ref": "#/components/parameters/ReadId"}
    assert shared.paths["/courses"].get.responses["403"] == %{"$ref": "#/components/responses/Forbidden"}
    assert shared.components.responses[:Forbidden] == inline.paths["/courses"].get.responses["403"]
    assert shared.components.parameters[:ReadId] == hd(inline.paths["/courses/{id}"].get.parameters)

    for {_path, methods} <- shared.paths, {_method, operation} <- methods do
      assert operation.responses["401"] == %{"$ref": "#/components/responses/Unauthorized"}
      assert operation.responses["403"] == %{"$ref": "#/components/responses/Forbidden"}
    end
  end

  test "conflicting shared definitions fail instead of making the contract iteration-order dependent" do
    operation = fn description ->
      %{parameters: [], responses: %{"403" => %{description: description}}}
    end

    spec = %{components: %{}, paths: %{"/one" => %{get: operation.("One")}, "/two" => %{get: operation.("Two")}}}

    assert_raise ArgumentError, ~r/conflicting OpenAPI component definitions/, fn ->
      Hawk.OpenApi.Components.extract(spec)
    end
  end

  test "application-owned paths are preserved verbatim even with global security" do
    path = %{get: %{summary: "References", responses: %{"200" => %{description: "Plain JSON"}}}}

    spec =
      Hawk.OpenApi.spec([Videdal.Courses],
        title: "Test API",
        security: [%{"bearerAuth" => []}],
        extra_paths: %{"/references" => path}
      )

    assert spec.paths["/references"] == path
  end

  test "every emitted internal component reference resolves" do
    spec =
      Hawk.OpenApi.spec([Videdal.Courses, Videdal.Students], title: "Test API", security: [%{"bearerAuth" => []}])
      |> Jason.encode!()
      |> Jason.decode!()

    for ref <- references(spec) do
      assert ref |> String.trim_leading("#/") |> String.split("/") |> Enum.reduce(spec, &Map.fetch!(&2, &1))
    end
  end

  defp references(map) when is_map(map),
    do: Map.get(map, "$ref", []) |> List.wrap() |> Kernel.++(Enum.flat_map(Map.values(map), &references/1))

  defp references(list) when is_list(list), do: Enum.flat_map(list, &references/1)
  defp references(_value), do: []

  defp expand(%{"$ref": "#/components/parameters/" <> name}, spec),
    do: expand(Map.fetch!(spec.components.parameters, String.to_existing_atom(name)), spec)

  defp expand(%{"$ref": "#/components/responses/" <> name}, spec),
    do: expand(Map.fetch!(spec.components.responses, String.to_existing_atom(name)), spec)

  defp expand(map, spec) when is_map(map) do
    map = if Map.has_key?(map, :schemas), do: Map.drop(map, [:parameters, :responses]), else: map
    Map.new(map, fn {key, value} -> {key, expand(value, spec)} end)
  end

  defp expand(list, spec) when is_list(list), do: Enum.map(list, &expand(&1, spec))
  defp expand(value, _spec), do: value
end
