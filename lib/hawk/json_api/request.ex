defmodule Hawk.JsonApi.Request do
  @moduledoc """
  Parses and validates JSON:API request payloads for Hawk resources.

  This is the request-side companion to `Hawk.JsonApi.Document`: it turns
  query params (`include`, `filter`, `sort`, `page`) into reader options,
  validates create/update documents against the resource's JSON:API contract,
  and extracts writer attrs from request bodies. ID handling (full UUIDs and
  read-only short-id prefixes) also lives here.

  The external shape used for validation is resolved through
  `Hawk.JsonApi.Schema.metadata/2`.
  """

  alias Hawk.JsonApi.Schema

  @doc """
  Validates that an `id` is a UUID, raising otherwise.
  """
  def validate_uuid!(id, label \\ "id") do
    case Ecto.UUID.cast(id) do
      {:ok, _uuid} -> id
      :error -> raise ArgumentError, "#{label} must be a valid UUID"
    end
  end

  @doc """
  Classifies a member `id` as a full UUID or an 8-character short-id prefix.
  """
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

  @doc """
  Builds a UUID range filter for a short-id prefix.

  The prefix is padded to a lower/upper UUID bound so the normal btree UUID
  index can be used instead of `id::text LIKE 'prefix%'`.
  """
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
      IO.iodata_to_binary([prefix, "-", "ffff", "-", "ffff", "-", "ffff", "-", String.duplicate("f", 12)])

    {:and, %{id: {:gte, lower}}, %{id: {:lte, upper}}}
  end

  @doc """
  Validates a create/update request document against the resource contract.
  """
  def validate_document!(params, model, capability, _opts \\ [])
      when capability in [:creatable, :updatable] do
    data = request_data!(params)
    json_api = Schema.metadata(model)

    validate_type!(data, json_api.type, capability)
    validate_attribute_members!(data, json_api, capability)
    validate_relationship_members!(data, model, json_api, capability)

    :ok
  end

  @doc """
  Extracts writer attrs from a create/update request document.
  """
  def attributes(params, model, capability, _opts \\ [])
      when capability in [:creatable, :updatable] do
    json_api = Schema.metadata(model)
    allowed = Map.fetch!(json_api, capability)
    data = Map.get(params, "data", %{})

    data
    |> Map.get("attributes", %{})
    |> atomize_allowed(allowed, json_api)
    |> Map.merge(relationship_attrs(model, data, allowed, json_api))
  end

  @doc """
  Parses JSON:API query params into reader options.
  """
  def request_options(params, opts \\ []) when is_map(params) and is_list(opts) do
    reader = Keyword.get(opts, :reader)

    []
    |> put_request_option(:page, parse_page(params), %{})
    |> put_request_option(:preloads, parse_include(Map.get(params, "include"), reader), [])
    |> put_request_option(:filter, parse_filter(Map.get(params, "filter")), :all)
    |> put_sort(Map.get(params, "sort"))
  end

  @doc """
  Parses JSON:API sparse fieldsets from `fields[type]=field,other_field` params.
  """
  def sparse_fieldsets(params) when is_map(params), do: parse_fields(Map.get(params, "fields"))

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

      validate_relationship_identifier!(model, Schema.relationship_source!(json_api, name), relationship)
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
    association = model.__hawk_schema__(:association, name)
    expected_type = Schema.metadata(association.related).type

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

  defp relationship_attrs(model, data, allowed, json_api) do
    allowed_by_name = Map.new(allowed, &{to_string(&1), &1})

    data
    |> Map.get("relationships", %{})
    |> Enum.reduce(%{}, fn {name, %{"data" => relationship}}, attrs ->
      case Map.fetch(allowed_by_name, name) do
        {:ok, key} ->
          source = Schema.relationship_source!(json_api, key)
          association = writable_relationship_association!(model, source)
          Map.put(attrs, association.owner_key, relationship_id(relationship))

        :error ->
          attrs
      end
    end)
  end

  defp writable_relationship_association!(model, source) do
    association = model.__hawk_schema__(:association, source)

    case association do
      %Ecto.Association.BelongsTo{} ->
        association

      _other ->
        raise ArgumentError,
              "relationship #{source} is not writable; only belongs_to relationships can be mapped to writer attrs"
    end
  end

  defp relationship_id(%{"id" => id}), do: id
  defp relationship_id(nil), do: nil

  defp put_request_option(opts, _key, value, value), do: opts
  defp put_request_option(opts, key, value, _empty), do: Keyword.put(opts, key, value)

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

  defp parse_fields(nil), do: %{}
  defp parse_fields(fields) when fields == %{}, do: %{}

  defp parse_fields(fields) when is_map(fields) do
    Map.new(fields, fn {type, fieldset} ->
      fields =
        fieldset
        |> to_string()
        |> String.split(",", trim: true)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> MapSet.new()

      {to_string(type), fields}
    end)
  end

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

  defp parse_include(nil, _reader), do: []
  defp parse_include("", _reader), do: []

  defp parse_include(include, reader) when is_binary(include) do
    include
    |> String.split(",", trim: true)
    |> Enum.map(&String.split(&1, ".", trim: true))
    |> Enum.map(&include_path_to_preload(&1, reader))
    |> Enum.reduce([], &merge_preload/2)
    |> Enum.reverse()
  end

  defp include_path_to_preload([segment], reader) do
    include_atom!(segment, reader)
  end

  defp include_path_to_preload([segment | rest], reader) do
    key = include_atom!(segment, reader)
    nested_reader = preload_reader(reader, key)

    {key, [include_path_to_preload(rest, nested_reader)]}
  end

  defp include_atom!(segment, nil), do: existing_param_atom!(segment, "include")

  defp include_atom!(segment, reader) do
    reader
    |> preload_keys()
    |> Enum.find(&(to_string(&1) == segment))
    |> case do
      nil -> raise ArgumentError, "unknown include #{inspect(segment)}"
      key -> key
    end
  end

  defp preload_keys(reader) do
    if Code.ensure_loaded?(reader) and function_exported?(reader, :preload_keys, 0) do
      reader.preload_keys()
    else
      MapSet.new()
    end
  end

  defp preload_reader(nil, _key), do: nil

  defp preload_reader(reader, key) do
    if Code.ensure_loaded?(reader) and
         function_exported?(reader, :preload_readers, 0) do
      Map.get(reader.preload_readers(), key)
    end
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

  defp uuid?(id), do: match?({:ok, _uuid}, Ecto.UUID.cast(id))
  defp short_id?(id), do: Regex.match?(~r/\A[0-9a-fA-F]{8}\z/, id)
end
