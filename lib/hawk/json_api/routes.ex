defmodule Hawk.JsonApi.Routes do
  @moduledoc """
  JSON:API route specs for Hawk resources.

  This is a framework-light route description layer. Phoenix router helpers can
  consume these specs later, while tests can already assert route/controller
  consistency without bringing Phoenix into Hawk's dependencies.
  """

  @doc """
  Returns the JSON:API route specs for a resource or list of resources.

  Each route is a map of `{method, path, action, capability, resource}`.
  `create`/`update`/`delete` are always present because the writer is a required
  sibling for every Hawk resource. `/-actions/:action` is also a stable dispatch
  route; the controller returns not found when no matching action exists. Used by
  `Hawk.OpenApi` and by tests asserting route/controller consistency.

  ## Options

    * `:path_prefix` — a prefix joined onto each path (default `""`).
  """
  def routes(resource_or_resources, opts \\ [])

  def routes(resources, opts) when is_list(resources) do
    Enum.flat_map(resources, &routes(&1, opts))
  end

  def routes(%{json_api: _json_api} = resource, opts) do
    resource_routes(resource, opts)
  end

  def routes(resource, opts) when is_atom(resource) do
    case normalize_resource(resource) do
      nil -> []
      route_resource -> resource_routes(route_resource, opts)
    end
  end

  defp normalize_resource(module) do
    Code.ensure_compiled(module)

    if function_exported?(module, :__hawk_resource__, 1) do
      normalize_facade(module)
    end
  end

  defp normalize_facade(resource) do
    case resource.__hawk_resource__(:json_api) do
      false ->
        nil

      json_api ->
        %{
          resource: resource,
          json_api: Hawk.JsonApi.Schema.metadata(json_api)
        }
    end
  end

  defp resource_routes(resource, opts) do
    collection_path = resource_path(opts, resource.json_api.type)
    member_path = collection_path <> "/:id"

    [
      route(resource, :get, collection_path, :index, :read),
      route(resource, :post, collection_path, :create, :write),
      route(resource, :get, member_path, :show, :read),
      route(resource, :patch, member_path, :update, :write),
      route(resource, :delete, member_path, :delete, :write),
      route(resource, :post, member_path <> "/-actions/:action", :action, :action),
      relationship_route(resource, member_path),
      related_route(resource, member_path)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp relationship_route(resource, member_path) do
    if map_size(resource.json_api.relationships) > 0 do
      route(resource, :get, member_path <> "/relationships/:relationship", :relationship, :read)
    end
  end

  defp related_route(resource, member_path) do
    if map_size(resource.json_api.relationships) > 0 do
      route(resource, :get, member_path <> "/:relationship", :related, :read)
    end
  end

  defp route(resource, method, path, action, capability) do
    %{
      method: method,
      path: path,
      action: action,
      controller_action: action,
      capability: capability,
      resource: resource.resource
    }
  end

  defp resource_path(opts, type) do
    opts
    |> Keyword.get(:path_prefix, "")
    |> Path.join(type)
    |> ensure_leading_slash()
  end

  defp ensure_leading_slash("/" <> _rest = path), do: path
  defp ensure_leading_slash(path), do: "/" <> path
end
