defmodule Hawk.ResourceContract do
  @moduledoc """
  Validates that a Hawk resource's declarations agree with its Ecto model.
  """

  def validate!(resource, model, opts \\ []) when is_atom(resource) and is_atom(model) do
    json_api = validate_model!(model, Hawk.JsonApi.Schema.metadata(model))
    reader = resource_module(resource, :reader, Reader)
    policy = resource_module(resource, :policy, Policy)

    validate_reader_preloads!(reader, json_api)
    maybe_validate_relationship_preloads!(reader, json_api, opts)
    validate_reader_sorts!(reader, model)
    validate_reader_filters!(reader, model)
    validate_policy_filters!(policy, reader)

    :ok
  end

  @doc """
  Validates a model's resolved JSON:API adapter against its schema, without
  requiring reader or policy modules.

  Useful for standalone models whose adapter is the only declared contract
  surface (e.g. computed-attribute resources).
  """
  def validate_model!(model) when is_atom(model) do
    validate_model!(model, Hawk.JsonApi.Schema.metadata(model))
  end

  defp validate_model!(model, json_api) when is_atom(model) do
    validate_json_api_attributes!(model, json_api)
    validate_json_api_relationships!(model, json_api)
    validate_write_fields!(json_api)
    validate_writable_relationships!(model, json_api)

    json_api
  end

  defp validate_json_api_attributes!(model, json_api) do
    schema_fields = model.__hawk_schema__(:fields) |> MapSet.new()

    json_api.attributes
    |> Enum.reject(fn {name, metadata} ->
      MapSet.member?(schema_fields, name) or computed_attribute?(metadata, schema_fields)
    end)
    |> Enum.map(fn {name, _metadata} -> name end)
    |> raise_if_any!("JSON:API attributes must be schema fields")
  end

  defp computed_attribute?(%{resolver: resolver}, _schema_fields) when is_function(resolver, 1),
    do: true

  defp computed_attribute?(%{resolver: resolver}, _schema_fields) when is_function(resolver, 2),
    do: true

  defp computed_attribute?(%{source: source}, schema_fields) when is_atom(source),
    do: MapSet.member?(schema_fields, source)

  defp computed_attribute?(_metadata, _schema_fields), do: false

  defp validate_json_api_relationships!(model, json_api) do
    associations = model.__hawk_schema__(:associations) |> MapSet.new()

    json_api.relationships
    |> Map.keys()
    |> Enum.reject(&MapSet.member?(associations, &1))
    |> raise_if_any!("JSON:API relationships must be schema associations")
  end

  defp validate_write_fields!(json_api) do
    exposed =
      json_api.attributes
      |> Map.keys()
      |> Kernel.++(Map.keys(json_api.relationships))
      |> MapSet.new()

    writable =
      [:creatable, :updatable]
      |> Enum.flat_map(&Map.fetch!(json_api, &1))
      |> Enum.uniq()

    writable
    |> Enum.reject(&MapSet.member?(exposed, &1))
    |> raise_if_any!("JSON:API writable fields must be declared attributes or relationships")
  end

  defp validate_writable_relationships!(model, json_api) do
    writable =
      [:creatable, :updatable]
      |> Enum.flat_map(&Map.fetch!(json_api, &1))
      |> Enum.uniq()
      |> MapSet.new()

    json_api.relationships
    |> Enum.reject(fn {name, metadata} ->
      source = Map.get(metadata, :source, name)

      not MapSet.member?(writable, name) or
        match?(%Ecto.Association.BelongsTo{}, model.__hawk_schema__(:association, source))
    end)
    |> Enum.map(fn {name, _metadata} -> name end)
    |> raise_if_any!("JSON:API writable relationships must be belongs_to associations")
  end

  defp validate_reader_preloads!(reader, json_api) do
    relationships = json_api.relationships |> Map.keys() |> MapSet.new()

    reader
    |> reader_values(:preload_keys)
    |> Enum.reject(&MapSet.member?(relationships, &1))
    |> raise_if_any!("reader preloads must be declared JSON:API relationships")
  end

  defp maybe_validate_relationship_preloads!(reader, json_api, opts) do
    if Keyword.get(opts, :require_relationship_preloads, false) do
      preloads = reader |> reader_values(:preload_keys) |> MapSet.new()

      json_api.relationships
      |> Map.keys()
      |> Enum.reject(&MapSet.member?(preloads, &1))
      |> raise_if_any!("JSON:API relationships must be declared reader preloads")
    end
  end

  defp validate_reader_sorts!(reader, model) do
    schema_fields = model.__hawk_schema__(:fields) |> MapSet.new()

    reader
    |> reader_values(:sort_keys)
    |> Enum.reject(&MapSet.member?(schema_fields, &1))
    |> raise_if_any!("reader sorts must be schema fields")
  end

  defp validate_reader_filters!(reader, model) do
    schema_fields = model.__hawk_schema__(:fields) |> MapSet.new()
    handlers = reader_values(reader, :filter_handlers) |> Map.keys() |> MapSet.new()

    reader
    |> reader_values(:filter_keys)
    |> Enum.reject(&(MapSet.member?(schema_fields, &1) or MapSet.member?(handlers, &1)))
    |> raise_if_any!("reader filters must be schema fields or custom filter handlers")
  end

  defp validate_policy_filters!(policy, reader) do
    declared_reader_filters =
      reader
      |> reader_values(:filter_keys)
      |> MapSet.new()
      |> MapSet.union(reader_values(reader, :filter_handlers) |> Map.keys() |> MapSet.new())

    policy
    |> policy_read_filters()
    |> Enum.reject(&MapSet.member?(declared_reader_filters, &1))
    |> raise_if_any!("policy read filters must be declared reader filters")
  end

  defp policy_read_filters(policy) do
    if Code.ensure_loaded?(policy) and function_exported?(policy, :__hawk_policy__, 0) do
      policy.__hawk_policy__()
      |> Map.fetch!(:read)
      |> Enum.flat_map(&policy_role_filter_keys/1)
      |> Enum.uniq()
    else
      []
    end
  end

  defp policy_role_filter_keys({_role, :all}), do: []

  defp policy_role_filter_keys({_role, {:scoped, scopes, filter}}) do
    Enum.map(scopes, &policy_scope_filter_key/1) ++ Map.keys(filter)
  end

  defp policy_scope_filter_key({filter_key, _scope_key}), do: filter_key
  defp policy_scope_filter_key(scope_key) when is_atom(scope_key), do: scope_key

  defp resource_module(resource, key, suffix) do
    if Code.ensure_loaded?(resource) and function_exported?(resource, :__hawk_resource__, 1) do
      case resource.__hawk_resource__(key) do
        false -> Module.concat(resource, suffix)
        module -> module
      end
    else
      Module.concat(resource, suffix)
    end
  end

  defp reader_values(reader, function) do
    if Code.ensure_loaded?(reader) and function_exported?(reader, function, 0) do
      apply(reader, function, [])
    else
      []
    end
  end

  defp raise_if_any!([], _message), do: :ok

  defp raise_if_any!(values, message) do
    inspected = values |> Enum.sort() |> Enum.map_join(", ", &inspect/1)
    raise ArgumentError, "#{message}: #{inspected}"
  end
end
