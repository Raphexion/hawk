defmodule Hawk.JsonApiRouterTest.FakeRouter do
  defmacro __using__(_opts) do
    quote do
      import Hawk.JsonApiRouterTest.FakeRouter, only: [get: 3, get: 4, post: 3, patch: 3, delete: 3]
      Module.register_attribute(__MODULE__, :fake_routes, accumulate: true)
      @before_compile Hawk.JsonApiRouterTest.FakeRouter
    end
  end

  defmacro get(path, controller, action), do: route(:get, path, controller, action)

  defmacro get(path, controller, action, opts) do
    {opts, _binding} = Code.eval_quoted(opts, [], __CALLER__)
    route(:get, path, controller, action, opts)
  end

  defmacro post(path, controller, action), do: route(:post, path, controller, action)
  defmacro patch(path, controller, action), do: route(:patch, path, controller, action)
  defmacro delete(path, controller, action), do: route(:delete, path, controller, action)

  defmacro __before_compile__(_env) do
    quote do
      def __fake_routes__, do: Enum.reverse(@fake_routes)
    end
  end

  defp route(method, path, controller, action, opts \\ []) do
    if opts == [] do
      quote do
        @fake_routes {unquote(method), unquote(path), unquote(controller), unquote(action)}
      end
    else
      quote do
        @fake_routes {unquote(method), unquote(path), unquote(controller), unquote(action),
                      unquote(Macro.escape(opts))}
      end
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

  hawk_json_api(Videdal.CourseCatalog, Videdal.Controllers.CourseCatalogController, path_prefix: "/api/v1")
end

defmodule Hawk.JsonApiRouterTest.QueryRouter do
  use Hawk.JsonApiRouterTest.FakeRouter
  import Hawk.JsonApi.Router

  hawk_query("/similar-courses", Videdal.SimilarCourses, public: true)
end

defmodule Hawk.JsonApiRouterTest.HiddenRouter do
  use Hawk.JsonApiRouterTest.FakeRouter
  import Hawk.JsonApi.Router

  hawk_json_api(Videdal.InternalNotes, Videdal.Controllers.CourseCatalogController)
end

defmodule Hawk.JsonApiRouterTest do
  use ExUnit.Case, async: true

  alias Hawk.JsonApiRouterTest.{FullRouter, HiddenRouter, QueryRouter, ReadOnlyRouter}

  test "router macro emits full resource routes" do
    assert FullRouter.__fake_routes__() == [
             {:get, "/courses", Videdal.Controllers.CourseRoutesController, :index},
             {:post, "/courses", Videdal.Controllers.CourseRoutesController, :create},
             {:get, "/courses/:id", Videdal.Controllers.CourseRoutesController, :show},
             {:patch, "/courses/:id", Videdal.Controllers.CourseRoutesController, :update},
             {:delete, "/courses/:id", Videdal.Controllers.CourseRoutesController, :delete},
             {:post, "/courses/:id/-actions/:action", Videdal.Controllers.CourseRoutesController, :hawk_action},
             {:get, "/courses/:id/relationships/:relationship", Videdal.Controllers.CourseRoutesController,
              :relationship},
             {:get, "/courses/:id/:relationship", Videdal.Controllers.CourseRoutesController, :related}
           ]
  end

  test "router macro emits write routes and applies prefixes" do
    assert ReadOnlyRouter.__fake_routes__() == [
             {:get, "/api/v1/course-catalog", Videdal.Controllers.CourseCatalogController, :index},
             {:post, "/api/v1/course-catalog", Videdal.Controllers.CourseCatalogController, :create},
             {:get, "/api/v1/course-catalog/:id", Videdal.Controllers.CourseCatalogController, :show},
             {:patch, "/api/v1/course-catalog/:id", Videdal.Controllers.CourseCatalogController, :update},
             {:delete, "/api/v1/course-catalog/:id", Videdal.Controllers.CourseCatalogController, :delete},
             {:post, "/api/v1/course-catalog/:id/-actions/:action", Videdal.Controllers.CourseCatalogController,
              :hawk_action},
             {:get, "/api/v1/course-catalog/:id/relationships/:relationship",
              Videdal.Controllers.CourseCatalogController, :relationship},
             {:get, "/api/v1/course-catalog/:id/:relationship", Videdal.Controllers.CourseCatalogController, :related}
           ]
  end

  test "router macro emits generated query route without an application controller" do
    assert QueryRouter.__fake_routes__() == [
             {:get, "/similar-courses", Hawk.JsonApi.QueryController, :index,
              [private: %{hawk_query: Videdal.SimilarCourses, hawk_public?: true}]}
           ]
  end

  test "router macro tolerates query modules that compile later" do
    {[{router, _binary}], output} =
      ExUnit.CaptureIO.with_io(:stderr, fn ->
        Code.compile_string("""
        defmodule Hawk.JsonApiRouterTest.FutureQueryRouter do
          use Hawk.JsonApiRouterTest.FakeRouter
          import Hawk.JsonApi.Router

          hawk_query "/future-query", Hawk.JsonApiRouterTest.FutureQuery, public: true
        end
        """)
      end)

    assert output =~ "skipping router validation"

    assert router.__fake_routes__() == [
             {:get, "/future-query", Hawk.JsonApi.QueryController, :index,
              [private: %{hawk_query: Hawk.JsonApiRouterTest.FutureQuery, hawk_public?: true}]}
           ]
  end

  test "router macro validates emitted controller actions" do
    assert_raise ArgumentError,
                 ~r/Hawk JSON:API router controller Hawk.JsonApiRouterTest.IncompleteController must define create\/2 for post \/course-catalog/,
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
