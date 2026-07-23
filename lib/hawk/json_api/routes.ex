defmodule Hawk.JsonApi.Routes do
  @moduledoc """
  Resource-capability-aware JSON:API route specs.

  This is a framework-light route description layer. Phoenix router helpers can
  consume these specs later, while tests can already assert route/capability
  consistency without bringing Phoenix into Hawk's dependencies.
  """

  def routes(resource_or_resources, opts \\ [])

  def routes(resources, opts) when is_list(resources) do
    Enum.flat_map(resources, &routes(&1, opts))
  end

  def routes(%{json_api: _json_api, capabilities: _capabilities} = resource, opts) do
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

    cond do
      function_exported?(module, :__hawk_resource__, 1) ->
        normalize_facade(module)

      function_exported?(module, :__hawk_json_api__, 0) ->
        %{
          resource: module.__hawk_resource__(),
          json_api: Hawk.JsonApi.Schema.metadata(module),
          capabilities: %{writer: true, actions: true}
        }

      true ->
        nil
    end
  end

  defp normalize_facade(resource) do
    case resource.__hawk_resource__(:json_api) do
      false ->
        nil

      json_api ->
        %{
          resource: resource,
          json_api: Hawk.JsonApi.Schema.metadata(json_api),
          capabilities: resource.__hawk_resource__(:capabilities)
        }
    end
  end

  defp resource_routes(resource, opts) do
    collection_path = resource_path(opts, resource.json_api.type)
    member_path = collection_path <> "/:id"

    [
      route(resource, :get, collection_path, :index, :read),
      writer_route(resource, :create, route(resource, :post, collection_path, :create, :write)),
      route(resource, :get, member_path, :show, :read),
      writer_route(resource, :update, route(resource, :patch, member_path, :update, :write)),
      writer_route(resource, :delete, route(resource, :delete, member_path, :delete, :write)),
      action_route(resource, member_path),
      relationship_route(resource, member_path),
      related_route(resource, member_path)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp writer_route(%{capabilities: %{writer: true}}, _action, route), do: route
  defp writer_route(_resource, _action, _route), do: nil

  defp action_route(%{capabilities: %{actions: true}} = resource, member_path),
    do: route(resource, :post, member_path <> "/-actions/:action", :action, :action)

  defp action_route(_resource, _member_path), do: nil

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
