defmodule Hawk.JsonApi do
  @moduledoc """
  JSON:API metadata and documentation helpers.

  This module starts with documentation/schema generation from `Hawk.Model`
  declarations. Runtime request/response helpers can build on the same metadata.
  """

  def document(models, opts \\ [])

  def document(models, opts) when is_list(models) do
    %{data: Enum.map(models, &resource_object(&1, opts))}
  end

  def document(model, opts) when is_struct(model) do
    %{data: resource_object(model, opts)}
  end

  def attributes(params, model, capability) when capability in [:creatable, :updatable] do
    json_api = model.__hawk_json_api__()
    allowed = Map.fetch!(json_api, capability)
    data = Map.get(params, "data", %{})

    data
    |> Map.get("attributes", %{})
    |> atomize_allowed(allowed)
    |> Map.merge(relationship_attrs(model, data, allowed))
  end

  def request_options(params) when is_map(params) do
    []
    |> put_request_option(:page, parse_page(params), %{})
    |> put_request_option(:preloads, parse_include(Map.get(params, "include")), [])
    |> put_sort(Map.get(params, "sort"))
  end

  def openapi_index_operation(model) when is_atom(model) do
    %{
      parameters: [
        %{name: "sort", schema: %{enum: sort_values(model)}},
        %{name: "page[size]", schema: %{type: "integer", minimum: 0}},
        %{name: "page[number]", schema: %{type: "integer", minimum: 1}},
        %{name: "page_size", schema: %{type: "integer", minimum: 0}}
      ]
    }
  end

  def openapi_schema(model) when is_atom(model) do
    json_api = model.__hawk_json_api__()

    %{
      "type" => "object",
      "description" => Map.get(json_api, :doc),
      "properties" => properties(json_api)
    }
  end

  defp resource_object(model, opts) do
    json_api = model.__struct__.__hawk_json_api__()

    %{
      type: json_api.type,
      id: to_string(Map.get(model, :id)),
      attributes: resource_attributes(model, json_api),
      relationships: resource_relationships(model, json_api, Keyword.get(opts, :preloads, []))
    }
  end

  defp resource_attributes(model, json_api) do
    Map.new(json_api.attributes, fn {name, _metadata} -> {name, Map.get(model, name)} end)
  end

  defp resource_relationships(model, json_api, preloads) do
    Map.new(json_api.relationships, fn {name, _metadata} ->
      {name, %{data: relationship_data(model, name, preloads)}}
    end)
  end

  defp relationship_data(model, name, preloads) do
    association = model.__struct__.__schema__(:association, name)

    case association.cardinality do
      :one -> belongs_to_identifier(model, association)
      :many -> many_identifiers(Map.get(model, name), preload_requested?(preloads, name))
    end
  end

  defp belongs_to_identifier(model, association) do
    id = Map.get(model, association.owner_key)
    type = association.related.__hawk_json_api__().type

    if is_nil(id), do: nil, else: %{type: type, id: to_string(id)}
  end

  defp many_identifiers(_models, false), do: []
  defp many_identifiers(%Ecto.Association.NotLoaded{}, true), do: []
  defp many_identifiers(nil, true), do: []

  defp many_identifiers(models, true),
    do:
      Enum.map(
        models,
        &%{type: &1.__struct__.__hawk_json_api__().type, id: to_string(Map.get(&1, :id))}
      )

  defp preload_requested?(preloads, name) do
    Enum.any?(preloads, fn
      ^name -> true
      {^name, _nested} -> true
      _other -> false
    end)
  end

  defp atomize_allowed(attrs, allowed) do
    Map.new(attrs, fn {key, value} -> {String.to_atom(key), value} end)
    |> Map.take(allowed)
  end

  defp relationship_attrs(model, data, allowed) do
    data
    |> Map.get("relationships", %{})
    |> Enum.reduce(%{}, fn {name, %{"data" => relationship}}, attrs ->
      key = String.to_atom(name)

      if key in allowed do
        association = model.__schema__(:association, key)
        Map.put(attrs, association.owner_key, relationship_id(relationship))
      else
        attrs
      end
    end)
  end

  defp relationship_id(%{"id" => id}), do: parse_id(id)
  defp relationship_id(nil), do: nil

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {integer, ""} -> integer
      _other -> id
    end
  end

  defp parse_id(id), do: id

  defp put_request_option(opts, _key, value, value), do: opts
  defp put_request_option(opts, key, value, _empty), do: Keyword.put(opts, key, value)

  defp put_pagination_meta(document, models, opts) do
    case Keyword.get(opts, :page) do
      nil ->
        document

      page ->
        Map.put(document, :meta, %{
          page: %{
            size: Map.get(page, :size),
            number: Map.get(page, :number, 1),
            count: length(models)
          }
        })
    end
  end

  defp put_sort(opts, nil), do: opts
  defp put_sort(opts, ""), do: opts

  defp put_sort(opts, "-" <> column) do
    Keyword.put(
      opts,
      :page,
      Map.merge(Keyword.get(opts, :page, %{}), %{column: String.to_atom(column), dir: :desc})
    )
  end

  defp put_sort(opts, column) do
    Keyword.put(
      opts,
      :page,
      Map.merge(Keyword.get(opts, :page, %{}), %{column: String.to_atom(column), dir: :asc})
    )
  end

  defp parse_page(params) do
    page = Map.get(params, "page", %{})

    %{}
    |> put_page_value(:size, Map.get(page, "size") || Map.get(params, "page_size"))
    |> put_page_value(:number, Map.get(page, "number") || Map.get(params, "page_number"))
  end

  defp put_page_value(page, _key, nil), do: page
  defp put_page_value(page, key, value) when is_integer(value), do: Map.put(page, key, value)

  defp put_page_value(page, key, value) when is_binary(value),
    do: Map.put(page, key, String.to_integer(value))

  defp parse_include(nil), do: []
  defp parse_include(""), do: []

  defp parse_include(include) when is_binary(include) do
    include
    |> String.split(",", trim: true)
    |> Enum.map(&String.split(&1, ".", trim: true))
    |> Enum.map(&include_path_to_preload/1)
    |> Enum.reduce([], &merge_preload/2)
    |> Enum.reverse()
  end

  defp include_path_to_preload([segment]) do
    String.to_atom(segment)
  end

  defp include_path_to_preload([segment | rest]) do
    {String.to_atom(segment), [include_path_to_preload(rest)]}
  end

  defp merge_preload(preload, acc) when is_atom(preload) do
    if Enum.any?(acc, &preload_key?(&1, preload)), do: acc, else: [preload | acc]
  end

  defp merge_preload({key, nested}, acc) do
    case Enum.split_with(acc, &preload_key?(&1, key)) do
      {[], rest} ->
        [{key, nested} | rest]

      {[existing], rest} ->
        [{key, merge_nested_preloads(existing, nested)} | rest]
    end
  end

  defp preload_key?({key, _nested}, key), do: true
  defp preload_key?(key, key), do: true
  defp preload_key?(_preload, _key), do: false

  defp merge_nested_preloads({_key, existing}, nested),
    do: nested |> Enum.reduce(existing, &merge_preload/2) |> Enum.reverse()

  defp merge_nested_preloads(_key, nested), do: nested

  defp sort_values(model) do
    model
    |> reader_module()
    |> sort_keys()
    |> Enum.flat_map(fn key -> [to_string(key), "-#{key}"] end)
  end

  defp reader_module(model), do: Module.concat(model.__hawk_resource__(), Reader)

  defp sort_keys(reader) do
    if Code.ensure_loaded?(reader) and function_exported?(reader, :sort_keys, 0) do
      reader.sort_keys() |> Enum.sort()
    else
      [:id]
    end
  end

  defp properties(json_api) do
    json_api
    |> Map.take([:attributes, :relationships])
    |> Map.values()
    |> Enum.reduce(%{}, &Map.merge(&2, openapi_properties(&1)))
  end

  defp openapi_properties(fields) do
    Map.new(fields, fn {name, metadata} ->
      {to_string(name), openapi_property(metadata)}
    end)
  end

  defp openapi_property(metadata) do
    %{}
    |> put_optional("description", metadata, :doc)
    |> put_optional("example", metadata, :example)
  end

  defp put_optional(target, key, source, source_key) do
    case Map.fetch(source, source_key) do
      {:ok, value} -> Map.put(target, key, value)
      :error -> target
    end
  end
end
