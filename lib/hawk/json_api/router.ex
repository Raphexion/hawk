defmodule Hawk.JsonApi.Router do
  @moduledoc """
  Router macro adapter for Hawk JSON:API resource route specs.

  The macro emits ordinary router DSL calls (`get/3`, `post/3`, `patch/3`,
  `delete/3`) from `Hawk.JsonApi.Routes`. Phoenix routers can use those calls,
  and tests can exercise the same behavior with a tiny fake router DSL.
  """

  alias Hawk.JsonApi.Routes

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
