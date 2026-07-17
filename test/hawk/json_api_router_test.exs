defmodule Hawk.JsonApiRouterTest.FakeRouter do
  defmacro __using__(_opts) do
    quote do
      import Hawk.JsonApiRouterTest.FakeRouter, only: [get: 3, post: 3, patch: 3, delete: 3]
      Module.register_attribute(__MODULE__, :fake_routes, accumulate: true)
      @before_compile Hawk.JsonApiRouterTest.FakeRouter
    end
  end

  defmacro get(path, controller, action), do: route(:get, path, controller, action)
  defmacro post(path, controller, action), do: route(:post, path, controller, action)
  defmacro patch(path, controller, action), do: route(:patch, path, controller, action)
  defmacro delete(path, controller, action), do: route(:delete, path, controller, action)

  defmacro __before_compile__(_env) do
    quote do
      def __fake_routes__, do: Enum.reverse(@fake_routes)
    end
  end

  defp route(method, path, controller, action) do
    quote do
      @fake_routes {unquote(method), unquote(path), unquote(controller), unquote(action)}
    end
  end
end

defmodule Hawk.JsonApiRouterTest.FullRouter do
  use Hawk.JsonApiRouterTest.FakeRouter
  import Hawk.JsonApi.Router

  hawk_json_api(Videdal.Courses, Videdal.Controllers.CourseRoutesController)
end

defmodule Hawk.JsonApiRouterTest.ReadOnlyRouter do
  use Hawk.JsonApiRouterTest.FakeRouter
  import Hawk.JsonApi.Router

  hawk_json_api(Videdal.CourseCatalog, Videdal.Controllers.CourseCatalogController,
    path_prefix: "/api/v1"
  )
end

defmodule Hawk.JsonApiRouterTest.HiddenRouter do
  use Hawk.JsonApiRouterTest.FakeRouter
  import Hawk.JsonApi.Router

  hawk_json_api(Videdal.InternalNotes, Videdal.Controllers.CourseCatalogController)
end

defmodule Hawk.JsonApiRouterTest do
  use ExUnit.Case, async: true

  alias Hawk.JsonApiRouterTest.{FullRouter, HiddenRouter, ReadOnlyRouter}

  test "router macro emits full resource routes" do
    assert FullRouter.__fake_routes__() == [
             {:get, "/courses", Videdal.Controllers.CourseRoutesController, :index},
             {:post, "/courses", Videdal.Controllers.CourseRoutesController, :create},
             {:get, "/courses/:id", Videdal.Controllers.CourseRoutesController, :show},
             {:patch, "/courses/:id", Videdal.Controllers.CourseRoutesController, :update},
             {:delete, "/courses/:id", Videdal.Controllers.CourseRoutesController, :delete},
             {:post, "/courses/:id/-actions/:action", Videdal.Controllers.CourseRoutesController,
              :action},
             {:get, "/courses/:id/relationships/:relationship",
              Videdal.Controllers.CourseRoutesController, :relationship},
             {:get, "/courses/:id/:relationship", Videdal.Controllers.CourseRoutesController,
              :related}
           ]
  end

  test "router macro omits unsupported read-only routes and applies prefixes" do
    assert ReadOnlyRouter.__fake_routes__() == [
             {:get, "/api/v1/course-catalog", Videdal.Controllers.CourseCatalogController,
              :index},
             {:get, "/api/v1/course-catalog/:id", Videdal.Controllers.CourseCatalogController,
              :show},
             {:get, "/api/v1/course-catalog/:id/relationships/:relationship",
              Videdal.Controllers.CourseCatalogController, :relationship},
             {:get, "/api/v1/course-catalog/:id/:relationship",
              Videdal.Controllers.CourseCatalogController, :related}
           ]
  end

  test "router macro validates emitted controller actions" do
    assert_raise ArgumentError,
                 ~r/Hawk JSON:API router controller Hawk.JsonApiRouterTest.IncompleteController must define relationship\/2 for get \/course-catalog\/:id\/relationships\/:relationship/,
                 fn ->
                   Code.compile_string("""
                   defmodule Hawk.JsonApiRouterTest.IncompleteController do
                     def index(conn, params), do: {conn, params}
                     def show(conn, params), do: {conn, params}
                   end

                   defmodule Hawk.JsonApiRouterTest.InvalidRouter do
                     use Hawk.JsonApiRouterTest.FakeRouter
                     import Hawk.JsonApi.Router

                     hawk_json_api Videdal.CourseCatalog, Hawk.JsonApiRouterTest.IncompleteController
                   end
                   """)
                 end
  end

  test "router macro emits nothing for json_api disabled resources" do
    assert HiddenRouter.__fake_routes__() == []
  end
end
