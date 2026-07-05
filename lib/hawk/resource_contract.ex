defmodule Hawk.ResourceContract do
  @moduledoc """
  Validates that a Hawk resource's declarations agree with its Ecto model.
  """

  def validate!(resource, model) when is_atom(resource) and is_atom(model) do
    json_api = model.__hawk_json_api__()
    reader = Module.concat(resource, Reader)

    validate_json_api_attributes!(model, json_api)
    validate_json_api_relationships!(model, json_api)
    validate_write_fields!(json_api)
    validate_reader_preloads!(reader, json_api)
    validate_reader_sorts!(reader, model)
    validate_reader_filters!(reader, model)

    :ok
  end

  defp validate_json_api_attributes!(model, json_api) do
    schema_fields = model.__schema__(:fields) |> MapSet.new()

    json_api.attributes
    |> Map.keys()
    |> Enum.reject(&MapSet.member?(schema_fields, &1))
    |> raise_if_any!("JSON:API attributes must be schema fields")
  end

  defp validate_json_api_relationships!(model, json_api) do
    associations = model.__schema__(:associations) |> MapSet.new()

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

    [:creatable, :updatable]
    |> Enum.flat_map(&Map.fetch!(json_api, &1))
    |> Enum.uniq()
    |> Enum.reject(&MapSet.member?(exposed, &1))
    |> raise_if_any!("JSON:API writable fields must be declared attributes or relationships")
  end

  defp validate_reader_preloads!(reader, json_api) do
    relationships = json_api.relationships |> Map.keys() |> MapSet.new()

    reader
    |> reader_values(:preload_keys)
    |> Enum.reject(&MapSet.member?(relationships, &1))
    |> raise_if_any!("reader preloads must be declared JSON:API relationships")
  end

  defp validate_reader_sorts!(reader, model) do
    schema_fields = model.__schema__(:fields) |> MapSet.new()

    reader
    |> reader_values(:sort_keys)
    |> Enum.reject(&MapSet.member?(schema_fields, &1))
    |> raise_if_any!("reader sorts must be schema fields")
  end

  defp validate_reader_filters!(reader, model) do
    schema_fields = model.__schema__(:fields) |> MapSet.new()
    handlers = reader_values(reader, :filter_handlers) |> Map.keys() |> MapSet.new()

    reader
    |> reader_values(:filter_keys)
    |> Enum.reject(&(MapSet.member?(schema_fields, &1) or MapSet.member?(handlers, &1)))
    |> raise_if_any!("reader filters must be schema fields or custom filter handlers")
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
