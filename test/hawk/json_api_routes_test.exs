defmodule Hawk.JsonApiRoutesTest do
  use ExUnit.Case, async: true

  alias Hawk.JsonApi.Routes

  test "routes include every JSON:API endpoint supported by a full resource" do
    assert Routes.routes(Videdal.Courses) == [
             %{method: :get, path: "/courses", action: :index},
             %{method: :post, path: "/courses", action: :create},
             %{method: :get, path: "/courses/:id", action: :show},
             %{method: :patch, path: "/courses/:id", action: :update},
             %{method: :delete, path: "/courses/:id", action: :delete},
             %{method: :post, path: "/courses/:id/-actions/:action", action: :action},
             %{
               method: :get,
               path: "/courses/:id/relationships/:relationship",
               action: :relationship
             },
             %{method: :get, path: "/courses/:id/:relationship", action: :related}
           ]
  end

  test "routes omit write and action endpoints when capabilities are absent" do
    assert Routes.routes(Videdal.CourseCatalog) == [
             %{method: :get, path: "/course-catalog", action: :index},
             %{method: :get, path: "/course-catalog/:id", action: :show},
             %{
               method: :get,
               path: "/course-catalog/:id/relationships/:relationship",
               action: :relationship
             },
             %{method: :get, path: "/course-catalog/:id/:relationship", action: :related}
           ]
  end

  test "routes omit resources with json_api disabled" do
    assert Routes.routes(Videdal.InternalNotes) == []
  end

  test "routes support path prefixes" do
    assert Routes.routes(Videdal.CourseCatalog, path_prefix: "/api/v1") == [
             %{method: :get, path: "/api/v1/course-catalog", action: :index},
             %{method: :get, path: "/api/v1/course-catalog/:id", action: :show},
             %{
               method: :get,
               path: "/api/v1/course-catalog/:id/relationships/:relationship",
               action: :relationship
             },
             %{method: :get, path: "/api/v1/course-catalog/:id/:relationship", action: :related}
           ]
  end
end
