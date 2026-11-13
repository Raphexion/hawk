defmodule Hawk.JsonApi.Registry do
  @moduledoc """
  A shared list of resource facades and controllers for routing and OpenAPI.

      defmodule MyApp.ApiRegistry do
        use Hawk.JsonApi.Registry
        resource(MyApp.Courses, MyAppWeb.CoursesController)
        resource(MyApp.Teachers, MyAppWeb.TeachersController)
      end

  In a Phoenix router, call
  `Hawk.JsonApi.Router.hawk_json_api_registry(MyApp.ApiRegistry)` after requiring
  or importing `Hawk.JsonApi.Router`. Generate the matching document with
  `Hawk.OpenApi.spec(MyApp.ApiRegistry, title: "My API")`.

  Controller names must be fully qualified. Pass the same `path_prefix:` to
  routing and OpenAPI; include any enclosing Phoenix scope in OpenAPI's prefix.
  Existing individual route declarations and resource lists remain supported.
  Registries describe the default JSON:API presentation of each facade.
  """

  defmacro __using__(_opts) do
    quote do
      import Hawk.JsonApi.Registry, only: [resource: 2]
      Module.register_attribute(__MODULE__, :hawk_api_entries, accumulate: true)
      @before_compile Hawk.JsonApi.Registry
    end
  end

  @doc "Registers a resource facade and its fully qualified controller."
  defmacro resource(resource, controller) do
    resource = Macro.expand(resource, __CALLER__)
    controller = Macro.expand(controller, __CALLER__)

    quote do
      @hawk_api_entries {unquote(resource), unquote(controller)}
    end
  end

  defmacro __before_compile__(env) do
    entries = env.module |> Module.get_attribute(:hawk_api_entries) |> Enum.reverse()
    resources = Enum.map(entries, &elem(&1, 0))

    if Enum.uniq(resources) != resources do
      raise ArgumentError, "JSON:API registry contains duplicate resources"
    end

    quote do
      def __hawk_json_api_registry__, do: unquote(Macro.escape(entries))
    end
  end

  @doc "Returns the registry's resource facades in declaration order."
  def resources(registry) do
    Code.ensure_compiled!(registry)
    Enum.map(registry.__hawk_json_api_registry__(), &elem(&1, 0))
  end
end
