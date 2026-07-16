defmodule Hawk.JsonApi do
  @moduledoc """
  JSON:API metadata and documentation helpers.

  This module starts with documentation/schema generation from `Hawk.Model`
  declarations. Runtime request/response helpers can build on the same metadata.
  """

  def document(models, opts \\ [])

  def document(models, opts) when is_list(models) do
    %{data: Enum.map(models, &resource_object(&1, opts))}
    |> put_document_links(models, opts)
    |> put_included(models, opts)
    |> put_pagination_meta(models, opts)
  end

  def document(model, opts) when is_struct(model) do
    %{data: resource_object(model, opts)}
    |> put_document_links([model], opts)
    |> put_included([model], opts)
  end

  def metadata(source, opts \\ [])

  def metadata(%module{}, opts), do: metadata(module, opts)

  def metadata(module, opts) when is_atom(module) do
    opts
    |> Keyword.get(:json_api_by_model, %{})
    |> Map.get(module, module.__hawk_json_api__())
    |> normalize_metadata()
  end

  def relationship_document(model, relationship)
      when is_struct(model) and is_binary(relationship) do
    name = relationship_key!(model, relationship)
    data = relationship_data(model, name, [name])

    %{
      links: relationship_links(model, metadata(model), name),
      data: data
    }
  end

  def related_document(model, relationship, opts \\ [])
      when is_struct(model) and is_binary(relationship) do
    name = relationship_key!(model, relationship)

    case related_value(model, name) do
      models when is_list(models) ->
        document(
          models,
          opts |> Keyword.put(:links, true) |> Keyword.put(:self, collection_path(model, name))
        )

      nil ->
        %{data: nil}

      related ->
        document(related, Keyword.put(opts, :links, true))
    end
  end

  def validate_uuid!(id, label \\ "id") do
    case Ecto.UUID.cast(id) do
      {:ok, _uuid} -> id
      :error -> raise ArgumentError, "#{label} must be a valid UUID"
    end
  end

  def member_id!(id) when is_binary(id) do
    cond do
      uuid?(id) ->
        {:uuid, id}

      short_id?(id) ->
        {:short_id, String.downcase(id)}

      true ->
        raise ArgumentError, "id must be a valid UUID or 8-character short id"
    end
  end

  def short_id_filter(prefix) when is_binary(prefix) do
    lower =
      IO.iodata_to_binary([
        prefix,
        "-",
        "0000",
        "-",
        "0000",
        "-",
        "0000",
        "-",
        String.duplicate("0", 12)
      ])

    upper =
      IO.iodata_to_binary([prefix, "-", "ffff", "-", "ffff", "-", "ffff", "-", "ffffffffffff"])

    {:and, %{id: {:gte, lower}}, %{id: {:lte, upper}}}
  end

  defp uuid?(id), do: match?({:ok, _uuid}, Ecto.UUID.cast(id))
  defp short_id?(id), do: Regex.match?(~r/\A[0-9a-fA-F]{8}\z/, id)

  def validate_document!(params, model, capability, opts \\ [])
      when capability in [:creatable, :updatable] do
    data = request_data!(params)
    json_api = metadata(model, opts)

    validate_type!(data, json_api.type, capability)
    validate_attribute_members!(data, json_api, capability)
    validate_relationship_members!(data, model, json_api, capability)

    :ok
  end

  def attributes(params, model, capability, opts \\ [])
      when capability in [:creatable, :updatable] do
    json_api = metadata(model, opts)
    allowed = Map.fetch!(json_api, capability)
    data = Map.get(params, "data", %{})

    data
    |> Map.get("attributes", %{})
    |> atomize_allowed(allowed, json_api)
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
    json_api = metadata(model, opts)

    %{
      type: json_api.type,
      id: to_string(Map.get(model, :id)),
      attributes: resource_attributes(model, json_api, opts),
      relationships: resource_relationships(model, json_api, opts)
    }
    |> put_resource_links(model, json_api, opts)
  end

  defp normalize_metadata(metadata) do
    Map.merge(%{attributes: %{}, relationships: %{}, creatable: [], updatable: []}, metadata)
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

  defp resource_relationships(model, json_api, opts) do
    preloads = Keyword.get(opts, :preloads, [])

    Map.new(json_api.relationships, fn {name, _metadata} ->
      relationship = %{data: relationship_data(model, name, preloads)}

      if Keyword.get(opts, :links, false) do
        {name, Map.put(relationship, :links, relationship_links(model, json_api, name))}
      else
        {name, relationship}
      end
    end)
  end

  defp relationship_data(model, name, preloads) do
    association = schema_module(model).__schema__(:association, name)

    case association.cardinality do
      :one -> belongs_to_identifier(model, association)
      :many -> many_identifiers(Map.get(model, name), preload_requested?(preloads, name))
    end
  end

  defp relationship_links(model, json_api, name) do
    base = resource_path(model, json_api)

    %{
      self: base <> "/relationships/" <> to_string(name),
      related: base <> "/" <> to_string(name)
    }
  end

  defp put_resource_links(resource, model, json_api, opts) do
    if Keyword.get(opts, :links, false) do
      Map.put(resource, :links, %{self: resource_path(model, json_api)})
    else
      resource
    end
  end

  defp put_document_links(document, [first | _models], opts) do
    if Keyword.get(opts, :links, false) do
      Map.put(document, :links, %{self: Keyword.get(opts, :self, document_self_link(first))})
    else
      document
    end
  end

  defp put_document_links(document, [], opts) do
    if Keyword.get(opts, :links, false) do
      Map.put(document, :links, %{self: Keyword.get(opts, :self, "/")})
    else
      document
    end
  end

  defp document_self_link(model) when is_struct(model), do: resource_path(model, metadata(model))

  defp collection_path(model, relationship) do
    association = schema_module(model).__schema__(:association, relationship)
    "/" <> metadata(association.related).type
  end

  defp resource_path(model, json_api) do
    "/" <> json_api.type <> "/" <> to_string(Map.get(model, :id))
  end

  defp belongs_to_identifier(model, association) do
    id = Map.get(model, association.owner_key)
    type = metadata(association.related).type

    if is_nil(id), do: nil, else: %{type: type, id: to_string(id)}
  end

  defp many_identifiers(_models, false), do: []
  defp many_identifiers(%Ecto.Association.NotLoaded{}, true), do: []
  defp many_identifiers(nil, true), do: []

  defp many_identifiers(models, true),
    do:
      Enum.map(
        models,
        &%{type: metadata(&1).type, id: to_string(Map.get(&1, :id))}
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

  defp request_data!(params) do
    case Map.get(params, "data") do
      data when is_map(data) -> data
      _other -> raise ArgumentError, "request document must include a data object"
    end
  end

  defp validate_type!(data, expected_type, :creatable) do
    case Map.get(data, "type") do
      ^expected_type -> :ok
      _other -> raise ArgumentError, "expected data.type to be #{inspect(expected_type)}"
    end
  end

  defp validate_type!(data, expected_type, :updatable) do
    case Map.get(data, "type") do
      nil -> :ok
      ^expected_type -> :ok
      _other -> raise ArgumentError, "expected data.type to be #{inspect(expected_type)}"
    end
  end

  defp validate_attribute_members!(data, json_api, capability) do
    attributes = Map.get(data, "attributes", %{})

    unless is_map(attributes) do
      raise ArgumentError, "data.attributes must be an object"
    end

    allowed = allowed_attribute_names(json_api, capability)

    attributes
    |> Map.keys()
    |> Enum.each(fn name ->
      unless MapSet.member?(allowed, name) do
        raise ArgumentError, "unknown attribute #{inspect(name)}"
      end
    end)
  end

  defp validate_relationship_members!(data, model, json_api, capability) do
    relationships = Map.get(data, "relationships", %{})

    unless is_map(relationships) do
      raise ArgumentError, "data.relationships must be an object"
    end

    allowed = allowed_relationship_names(json_api, capability)

    Enum.each(relationships, fn {name, relationship} ->
      unless MapSet.member?(allowed, name) do
        raise ArgumentError, "unknown relationship #{inspect(name)}"
      end

      validate_relationship_identifier!(model, String.to_existing_atom(name), relationship)
    end)
  end

  defp allowed_attribute_names(json_api, capability) do
    json_api
    |> Map.fetch!(capability)
    |> Enum.filter(&Map.has_key?(json_api.attributes, &1))
    |> Enum.map(&to_string/1)
    |> MapSet.new()
  end

  defp allowed_relationship_names(json_api, capability) do
    json_api
    |> Map.fetch!(capability)
    |> Enum.filter(&Map.has_key?(json_api.relationships, &1))
    |> Enum.map(&to_string/1)
    |> MapSet.new()
  end

  defp validate_relationship_identifier!(model, name, %{"data" => data}) do
    association = model.__schema__(:association, name)
    expected_type = association.related.__hawk_json_api__().type

    case {association.cardinality, data} do
      {:one, nil} ->
        :ok

      {:one, %{"type" => ^expected_type, "id" => id}} when not is_nil(id) ->
        validate_uuid!(id, "relationship #{name} id")

      {:one, %{"type" => other_type}} ->
        raise ArgumentError,
              "expected relationship #{name} type to be #{inspect(expected_type)}, got #{inspect(other_type)}"

      {:many, items} when is_list(items) ->
        Enum.each(items, &validate_many_relationship_identifier!(&1, name, expected_type))

      {:many, _other} ->
        raise ArgumentError, "relationship #{name} data must be an array"

      {:one, _other} ->
        raise ArgumentError,
              "relationship #{name} data must be null or a resource identifier object"
    end
  end

  defp validate_relationship_identifier!(_model, name, _relationship) do
    raise ArgumentError, "relationship #{name} must include data"
  end

  defp validate_many_relationship_identifier!(
         %{"type" => expected_type, "id" => id},
         name,
         expected_type
       )
       when not is_nil(id),
       do: validate_uuid!(id, "relationship #{name} id")

  defp validate_many_relationship_identifier!(%{"type" => other_type}, name, expected_type) do
    raise ArgumentError,
          "expected relationship #{name} type to be #{inspect(expected_type)}, got #{inspect(other_type)}"
  end

  defp validate_many_relationship_identifier!(_item, name, _expected_type) do
    raise ArgumentError, "relationship #{name} data must contain resource identifier objects"
  end

  defp atomize_allowed(attrs, allowed, json_api) do
    allowed_by_name = Map.new(allowed, &{to_string(&1), &1})

    attrs
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      case Map.fetch(allowed_by_name, key) do
        {:ok, field} -> Map.put(acc, writable_attribute_key(json_api, field), value)
        :error -> acc
      end
    end)
  end

  defp writable_attribute_key(json_api, field) do
    json_api.attributes
    |> Map.fetch!(field)
    |> Map.get(:source, field)
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

  defp relationship_id(%{"id" => id}), do: id
  defp relationship_id(nil), do: nil

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

  def relationship_key!(model, relationship) when is_struct(model) do
    relationship_key!(schema_module(model), relationship)
  end

  def relationship_key!(model, relationship) when is_atom(model) and is_binary(relationship) do
    allowed_by_name =
      model
      |> metadata()
      |> Map.fetch!(:relationships)
      |> Map.keys()
      |> Map.new(&{to_string(&1), &1})

    case Map.fetch(allowed_by_name, relationship) do
      {:ok, name} -> name
      :error -> raise ArgumentError, "unknown relationship #{inspect(relationship)}"
    end
  end

  defp schema_module(%module{}), do: module

  defp related_value(model, name) do
    case Map.get(model, name) do
      %Ecto.Association.NotLoaded{} -> nil
      value -> value
    end
  end

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
