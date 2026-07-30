defmodule Hawk.Plans.Spec do
  @moduledoc """
  Renders the resource-shaped plan operation manifest.

  This is a second renderer over `Hawk.JsonApi.Routes` + `Hawk.Actions`, sitting
  alongside `Hawk.OpenApi`. Where OpenAPI projects the resource surface to HTTP
  paths and operations, `Hawk.Plans.Spec` projects the same surface to
  resource-shaped plan ops an AI can compose into a batch and a human can review.

  The spec lists, per resource (by JSON:API `type`), the ops an authority can
  perform:

    * `:read` — with the reader's filters and sorts, for finding affected records
    * `:create` / `:update` / `:delete` — with creatable/updatable attrs and
      relationships (by external name, with `:source` and `:doc`)
    * `:action` — one per declared action, with name, doc, and params (the
      JSON:API `meta` wrapper already unwrapped)

  Capability filtering mirrors OpenAPI: resources with `json_api: false` are
  omitted, write ops are omitted when `writer` is disabled, action ops are
  omitted when `actions` is disabled. The executor validates plan ops against
  this spec, so authoring and execution read from the same symmetric surface —
  no drift.

  """

  alias Hawk.Actions
  alias Hawk.JsonApi.Schema

  @doc """
  Renders the plan operation manifest for the given resources.

  Resources are Hawk.Resource facades. Resources with `json_api: false` are
  omitted. The manifest is keyed by JSON:API `type`.
  """
  @spec spec([module()], keyword()) :: map()
  def spec(resources, opts \\ []) when is_list(resources) and is_list(opts) do
    resources
    |> Enum.map(&normalize_resource/1)
    |> Enum.reject(&is_nil/1)
    |> Map.new(fn resource -> {resource.json_api.type, resource_ops(resource)} end)
    |> then(fn resources_map -> %{resources: resources_map} end)
  end

  defp normalize_resource(module) when is_atom(module) do
    Code.ensure_compiled(module)

    if function_exported?(module, :__hawk_resource__, 1) do
      case module.__hawk_resource__(:json_api) do
        false ->
          nil

        json_api ->
          %{
            resource: module,
            json_api: Schema.metadata(json_api),
            capabilities: module.__hawk_resource__(:capabilities),
            identity: module.__hawk_resource__(:identity)
          }
      end
    end
  end

  @doc false
  def resource_ops(resource) do
    ops = []

    ops = ops ++ [read_op(resource)]

    # The writer is a required sibling for every Hawk resource, so write ops
    # are always part of the plan surface; the reviewer's policy gates them at
    # execution time.
    ops = ops ++ [create_op(resource), update_op(resource), delete_op()]

    ops =
      if resource.capabilities.actions,
        do: ops ++ action_ops(resource),
        else: ops

    %{
      type: resource.json_api.type,
      resource: resource.resource,
      ops: ops
    }
  end

  defp read_op(resource) do
    reader = Module.concat(resource.resource, Reader)

    {filters, sorts} =
      if Code.ensure_loaded?(reader) do
        {
          reader_values(reader, :filter_keys),
          reader_values(reader, :sort_keys)
        }
      else
        {[], []}
      end

    # The identity is always available as a filter and sort, even if the reader
    # doesn't declare it explicitly (it's the member-lookup key).
    filters = ensure_identity(filters, resource.identity)
    sorts = ensure_identity(sorts, resource.identity)

    %{op: :read, filters: Enum.sort(filters), sorts: Enum.sort(sorts)}
  end

  defp ensure_identity(keys, identity) do
    if identity in keys, do: keys, else: keys ++ [identity]
  end

  defp create_op(resource) do
    %{op: :create}
    |> put_attrs(resource, :creatable)
    |> put_relationships(resource, :creatable)
  end

  defp update_op(resource) do
    %{op: :update}
    |> put_attrs(resource, :updatable)
    |> put_relationships(resource, :updatable)
  end

  defp delete_op, do: %{op: :delete}

  defp action_ops(resource) do
    resource.resource
    |> Actions.actions()
    |> Enum.map(fn {name, metadata} ->
      %{
        op: :action,
        name: name,
        doc: metadata.doc,
        params: action_params(metadata)
      }
    end)
    |> Enum.sort_by(& &1.name)
  end

  defp action_params(metadata) do
    Map.new(metadata.params, fn {name, param_meta} ->
      {name, Map.take(param_meta, [:type, :doc, :example])}
    end)
  end

  defp put_attrs(op, resource, capability) do
    allowed = Map.fetch!(resource.json_api, capability)

    attrs =
      resource.json_api.attributes
      |> Map.take(allowed)
      |> Map.new(fn {name, metadata} ->
        {name, %{source: Map.get(metadata, :source, name), doc: Map.get(metadata, :doc)}}
      end)

    Map.put(op, :attrs, attrs)
  end

  defp put_relationships(op, resource, capability) do
    allowed = Map.fetch!(resource.json_api, capability)

    relationships =
      resource.json_api.relationships
      |> Map.take(allowed)
      |> Map.new(fn {name, metadata} ->
        source = Map.get(metadata, :source, name)
        target = resolve_relationship_target(resource, source)
        {name, %{source: source, doc: Map.get(metadata, :doc), target: target}}
      end)

    Map.put(op, :relationships, relationships)
  end

  defp resolve_relationship_target(resource, source) do
    model = resource.resource.__hawk_resource__(:model)

    case model.__schema__(:association, source) do
      %{related: related} -> Schema.metadata(related).type
      _no_association -> nil
    end
  end

  defp reader_values(reader, function) do
    if Code.ensure_loaded?(reader) and function_exported?(reader, function, 0) do
      apply(reader, function, []) |> Enum.to_list()
    else
      []
    end
  end
end
