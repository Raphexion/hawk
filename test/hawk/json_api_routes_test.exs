defmodule Hawk.JsonApiRoutesTest do
  use ExUnit.Case, async: true

  alias Hawk.JsonApi.Routes
  alias Videdal.Controllers.{CourseCatalogController, CourseRoutesController}

  test "routes include every JSON:API endpoint supported by a full resource" do
    assert Routes.routes(Videdal.Courses) == [
             route(:get, "/courses", :index, :read, Videdal.Courses),
             route(:post, "/courses", :create, :write, Videdal.Courses),
             route(:get, "/courses/:id", :show, :read, Videdal.Courses),
             route(:patch, "/courses/:id", :update, :write, Videdal.Courses),
             route(:delete, "/courses/:id", :delete, :write, Videdal.Courses),
             route(:post, "/courses/:id/-actions/:action", :action, :action, Videdal.Courses, :hawk_action),
             route(
               :get,
               "/courses/:id/relationships/:relationship",
               :relationship,
               :read,
               Videdal.Courses
             ),
             route(:get, "/courses/:id/:relationship", :related, :read, Videdal.Courses)
           ]
  end

  test "routes include the stable action dispatch endpoint" do
    assert Enum.any?(Routes.routes(Videdal.Courses), &(&1.action == :action))
  end

  test "globally read-only resources retain reads and omit every mutation route" do
    routes = Routes.routes(Videdal.CourseCatalog)

    assert Enum.map(routes, &{&1.method, &1.action}) == [
             get: :index,
             get: :show,
             get: :relationship,
             get: :related
           ]
  end

  test "role-scoped writes retain routes for authorized callers" do
    assert Enum.any?(Routes.routes(Videdal.Courses), &(&1.action == :create))
    assert Enum.any?(Routes.routes(Videdal.Courses), &(&1.action == :update))
    assert Enum.any?(Routes.routes(Videdal.Courses), &(&1.action == :delete))
    assert Enum.any?(Routes.routes(Videdal.Courses), &(&1.action == :action))
  end

  test "writable resources without actions omit the dispatcher" do
    assert Hawk.Actions.all_actions(Videdal.Teachers) == %{}
    routes = Routes.routes(Videdal.Teachers)
    assert Enum.any?(routes, &(&1.action == :create))
    refute Enum.any?(routes, &(&1.action == :action))
  end

  test "operation allowlists restrict routes without enabling globally forbidden writes" do
    metadata = Videdal.CourseCatalog.JsonApi.__hawk_json_api__()

    for operations <- [[], [:show], [:create, :update, :delete, :action]] do
      resource = %{resource: Videdal.CourseCatalog, json_api: Map.put(metadata, :operations, operations)}
      routes = Routes.routes(resource)
      assert Enum.all?(routes, &(&1.action in operations))
      refute Enum.any?(routes, &(&1.capability in [:write, :action]))
    end
  end

  test "invalid or duplicated operation declarations fail at compile time" do
    for operations <- [[:patch], [:show, :show]] do
      assert_raise ArgumentError, ~r/operations\/1 expects unique supported/, fn ->
        Code.compile_quoted(
          quote do
            defmodule Hawk.Test.InvalidApiOperations do
              use Hawk.JsonApi.Resource
              operations(unquote(operations))
            end
          end
        )
      end
    end
  end

  test "routes omit resources with json_api disabled" do
    assert Routes.routes(Videdal.InternalNotes) == []
  end

  test "routes support path prefixes" do
    assert Routes.routes(Videdal.CourseCatalog, path_prefix: "/api/v1") == [
             route(:get, "/api/v1/course-catalog", :index, :read, Videdal.CourseCatalog),
             route(:get, "/api/v1/course-catalog/:id", :show, :read, Videdal.CourseCatalog),
             route(
               :get,
               "/api/v1/course-catalog/:id/relationships/:relationship",
               :relationship,
               :read,
               Videdal.CourseCatalog
             ),
             route(
               :get,
               "/api/v1/course-catalog/:id/:relationship",
               :related,
               :read,
               Videdal.CourseCatalog
             )
           ]
  end

  test "emitted routes point at exported controller actions" do
    assert_controller_exports!(CourseRoutesController, Routes.routes(Videdal.Courses))
    assert_controller_exports!(CourseCatalogController, Routes.routes(Videdal.CourseCatalog))

    assert function_exported?(CourseCatalogController, :hawk_action, 2)
  end

  defp assert_controller_exports!(controller, routes) do
    Code.ensure_loaded!(controller)

    Enum.each(routes, fn route ->
      assert function_exported?(controller, route.controller_action, 2),
             "expected #{inspect(controller)} to export #{route.controller_action}/2"
    end)
  end

  defp route(method, path, action, capability, resource, controller_action \\ nil) do
    %{
      method: method,
      path: path,
      action: action,
      controller_action: controller_action || action,
      capability: capability,
      resource: resource
    }
  end
end
