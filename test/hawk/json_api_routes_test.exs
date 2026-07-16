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
             route(:post, "/courses/:id/-actions/:action", :action, :action, Videdal.Courses),
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

  test "routes omit write and action endpoints when capabilities are absent" do
    assert Routes.routes(Videdal.CourseCatalog) == [
             route(:get, "/course-catalog", :index, :read, Videdal.CourseCatalog),
             route(:get, "/course-catalog/:id", :show, :read, Videdal.CourseCatalog),
             route(
               :get,
               "/course-catalog/:id/relationships/:relationship",
               :relationship,
               :read,
               Videdal.CourseCatalog
             ),
             route(
               :get,
               "/course-catalog/:id/:relationship",
               :related,
               :read,
               Videdal.CourseCatalog
             )
           ]
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

    refute function_exported?(CourseCatalogController, :create, 2)
    refute function_exported?(CourseCatalogController, :update, 2)
    refute function_exported?(CourseCatalogController, :delete, 2)
    refute function_exported?(CourseCatalogController, :action, 2)
  end

  defp assert_controller_exports!(controller, routes) do
    Code.ensure_loaded!(controller)

    Enum.each(routes, fn route ->
      assert function_exported?(controller, route.controller_action, 2),
             "expected #{inspect(controller)} to export #{route.controller_action}/2"
    end)
  end

  defp route(method, path, action, capability, resource) do
    %{
      method: method,
      path: path,
      action: action,
      controller_action: action,
      capability: capability,
      resource: resource
    }
  end
end
