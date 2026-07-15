defmodule Hawk.JsonApi do
  @moduledoc """
  JSON:API metadata and documentation helpers.

  This module starts with documentation/schema generation from `Hawk.Model`
  declarations. Runtime request/response helpers can build on the same metadata.
  """

  def document(models, opts \\ [])

  def document(models, opts) when is_list(models) do
    %{data: Enum.map(models, &resource_object(&1, opts))}
    |> put_included(models, opts)
    |> put_pagination_meta(models, opts)
  end

  def document(model, opts) when is_struct(model) do
    %{data: resource_object(model, opts)}
    |> put_included([model], opts)
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
    |> put_request_option(:filter, parse_filter(Map.get(params, "filter")), :all)
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
      attributes: resource_attributes(model, json_api, opts),
      relationships: resource_relationships(model, json_api, Keyword.get(opts, :preloads, []))
    }
  end

  defp resource_attributes(model, json_api, opts) do
    Map.new(json_api.attributes, fn {name, metadata} ->
      {name, resource_attribute(model, name, metadata, opts)}
    end)
  end

  defp resource_attribute(model, _name, %{resolver: resolver}, opts)
       when is_function(resolver, 2),
       do: resolver.(model, opts)

  defp resource_attribute(model, _name, %{resolver: resolver}, _opts)
       when is_function(resolver, 1),
       do: resolver.(model)

  defp resource_attribute(model, _name, %{source: source}, _opts) when is_atom(source),
    do: Map.get(model, source)

  defp resource_attribute(model, name, _metadata, _opts), do: Map.get(model, name)

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

  defp put_included(document, models, opts) do
    included = included_resources(models, Keyword.get(opts, :preloads, []), opts)

    if included == [] do
      document
    else
      Map.put(document, :included, included)
    end
  end

  defp included_resources(models, preloads, opts) do
    models
    |> Enum.flat_map(&included_resources_for_model(&1, preloads, opts))
    |> Enum.uniq_by(&{&1.type, &1.id})
  end

  defp included_resources_for_model(model, preloads, opts) do
    Enum.flat_map(preloads, fn
      name when is_atom(name) ->
        direct_included_resources(model, name, [], opts)

      {name, nested} when is_atom(name) ->
        direct_included_resources(model, name, nested, opts)
    end)
  end

  defp direct_included_resources(model, name, nested, opts) do
    model
    |> related_models(name)
    |> Enum.flat_map(fn related ->
      [resource_object(related, Keyword.put(opts, :preloads, nested))] ++
        included_resources_for_model(related, nested, opts)
    end)
  end

  defp related_models(model, name) do
    case Map.get(model, name) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      models when is_list(models) -> models
      model -> [model]
    end
  end

  defp atomize_allowed(attrs, allowed) do
    allowed_by_name = Map.new(allowed, &{to_string(&1), &1})

    attrs
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      case Map.fetch(allowed_by_name, key) do
        {:ok, field} -> Map.put(acc, field, value)
        :error -> acc
      end
    end)
  end

  defp relationship_attrs(model, data, allowed) do
    allowed_by_name = Map.new(allowed, &{to_string(&1), &1})

    data
    |> Map.get("relationships", %{})
    |> Enum.reduce(%{}, fn {name, %{"data" => relationship}}, attrs ->
      case Map.fetch(allowed_by_name, name) do
        {:ok, key} ->
          association = model.__schema__(:association, key)
          Map.put(attrs, association.owner_key, relationship_id(relationship))

        :error ->
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
      Map.merge(Keyword.get(opts, :page, %{}), %{
        column: existing_param_atom!(column, "sort column"),
        dir: :desc
      })
    )
  end

  defp put_sort(opts, column) do
    Keyword.put(
      opts,
      :page,
      Map.merge(Keyword.get(opts, :page, %{}), %{
        column: existing_param_atom!(column, "sort column"),
        dir: :asc
      })
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

  defp parse_filter(nil), do: :all
  defp parse_filter(filter) when filter == %{}, do: :all

  defp parse_filter(filter) when is_map(filter) do
    Map.new(filter, fn {key, value} -> {parse_filter_key!(key), parse_filter_value!(value)} end)
  end

  defp parse_filter_key!(key) when is_atom(key), do: key

  defp parse_filter_key!(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError ->
      reraise ArgumentError, [message: "unknown filter key #{inspect(key)}"], __STACKTRACE__
  end

  defp parse_filter_value!(%{} = value) when map_size(value) == 1 do
    [{operator, operand}] = Map.to_list(value)
    {parse_filter_operator!(operator), parse_filter_scalar(operand)}
  end

  defp parse_filter_value!(value), do: parse_filter_scalar(value)

  defp parse_filter_operator!(operator) when is_atom(operator), do: operator

  defp parse_filter_operator!(operator)
       when operator in ["eq", "neq", "in", "not_in", "lt", "lte", "gt", "gte", "like", "ilike"] do
    String.to_existing_atom(operator)
  end

  defp parse_filter_operator!(operator),
    do: raise(ArgumentError, "unsupported filter operator #{inspect(operator)}")

  defp parse_filter_scalar("true"), do: true
  defp parse_filter_scalar("false"), do: false
  defp parse_filter_scalar(value), do: value

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
    existing_param_atom!(segment, "include")
  end

  defp include_path_to_preload([segment | rest]) do
    {existing_param_atom!(segment, "include"), [include_path_to_preload(rest)]}
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

  defp existing_param_atom!(value, label) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError ->
      reraise ArgumentError, [message: "unknown #{label} #{inspect(value)}"], __STACKTRACE__
  end

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
