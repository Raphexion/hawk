defmodule Hawk.JsonApiRegistryTest.Registry do
  use Hawk.JsonApi.Registry
  resource(Videdal.Courses, Videdal.Controllers.CourseRoutesController)
  resource(Videdal.CourseCatalog, Videdal.Controllers.CourseCatalogController)
end

defmodule Hawk.JsonApiRegistryTest.Router do
  use Phoenix.Router
  import Hawk.JsonApi.Router
  hawk_json_api_registry(Hawk.JsonApiRegistryTest.Registry, path_prefix: "/api/v1")
end

defmodule Hawk.JsonApiRegistryTest do
  use ExUnit.Case, async: true

  alias Hawk.JsonApiRegistryTest.{Registry, Router}

  test "one registry produces matching Phoenix and OpenAPI operations including every action" do
    assert Hawk.JsonApi.Registry.resources(Registry) == [Videdal.Courses, Videdal.CourseCatalog]
    spec = Hawk.OpenApi.spec(Registry, title: "Registry", path_prefix: "/api/v1")

    routed =
      Router.__routes__()
      |> Enum.flat_map(fn route ->
        path = Regex.replace(~r/:([a-z_]+)/, route.path, "{\\1}")

        if route.plug_opts == :hawk_action do
          Enum.map(Hawk.Actions.all_actions(Videdal.Courses), fn {name, _metadata} ->
            {route.verb, String.replace(path, "{action}", name)}
          end)
        else
          [{route.verb, path}]
        end
      end)
      |> MapSet.new()

    documented =
      spec.paths
      |> Enum.flat_map(fn {path, methods} -> Enum.map(methods, fn {method, _operation} -> {method, path} end) end)
      |> MapSet.new()

    assert routed == documented
    assert {:post, "/api/v1/courses/{id}/-actions/open-registration"} in routed
    refute {:post, "/api/v1/course-catalog"} in routed
  end

  test "duplicate resources fail when declaring a registry" do
    assert_raise ArgumentError, ~r/duplicate resources/, fn ->
      Code.compile_string("""
      defmodule Hawk.DuplicateApiRegistry do
        use Hawk.JsonApi.Registry
        resource(Videdal.Courses, Videdal.Controllers.CourseRoutesController)
        resource(Videdal.Courses, Videdal.Controllers.CourseRoutesController)
      end
      """)
    end
  end
end
