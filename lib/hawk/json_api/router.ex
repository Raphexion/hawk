defmodule Hawk.JsonApi.Router do
  @moduledoc """
  Router macro adapter for Hawk JSON:API resource route specs.

  `import Hawk.JsonApi.Router` inside a Phoenix router and call
  `hawk_json_api/3` to emit ordinary router DSL calls (`get/3`, `post/3`,
  `patch/3`, `delete/3`) from `Hawk.JsonApi.Routes`. The custom-action route is
  a stable dispatch route; the controller returns not found when no matching
  action exists.

  ## Example

      defmodule MyAppWeb.Router do
        use MyAppWeb, :router
        import Hawk.JsonApi.Router

        scope "/api/v1", MyAppWeb do
          hawk_json_api(Videdal.Courses, CoursesController)
        end
      end

  The controller must define a clause for each action the resource exposes
  (e.g. `index/2`, `show/2`); otherwise this macro raises at compile time.
  """

  alias Hawk.JsonApi.Routes

  @doc """
  Emits Phoenix router calls for every route in the resource's spec.

  ## Options

    * `:path_prefix` — passed through to `Hawk.JsonApi.Routes.routes/2`.
  """
  defmacro hawk_json_api(resource, controller, opts \\ []) do
    env = __CALLER__
    resource = Macro.expand(resource, env)
    controller = Macro.expand(controller, env)
    opts = Macro.expand(opts, env)
    routes = Routes.routes(resource, opts)

    validate_controller!(controller, routes)

    routes
    |> Enum.map(&quote_route(controller, &1))
    |> then(fn quoted_routes ->
      quote do
        (unquote_splicing(quoted_routes))
      end
    end)
  end

  defp validate_controller!(controller, routes) do
    Code.ensure_compiled(controller)

    Enum.each(routes, fn route ->
      unless function_exported?(controller, route.controller_action, 2) do
        raise ArgumentError,
              "Hawk JSON:API router controller #{inspect(controller)} must define #{route.controller_action}/2 for #{route.method} #{route.path}"
      end
    end)
  end

  defp quote_route(controller, route) do
    quote do
      unquote(route.method)(
        unquote(route.path),
        unquote(controller),
        unquote(route.controller_action)
      )
    end
  end
end
