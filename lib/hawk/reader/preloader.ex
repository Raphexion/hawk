defmodule Hawk.Reader.Preloader do
  @moduledoc false
  import Ecto.Query

  @type preload :: atom() | {atom(), [preload()]}

  @doc """
  Preloads requested associations through the host repo.

  Empty preload requests are a no-op. Unknown top-level preload keys fail loudly
  before the repo is called.
  """
  @spec preload([struct()], module(), [preload()], Enumerable.t()) :: [struct()]
  def preload(results, _repo, [], _allowed_keys), do: results

  def preload(results, repo, requested, allowed_keys) when is_list(requested) do
    validate_preloads!(requested, allowed_keys)
    repo.preload(results, requested)
  end

  def preload(_results, _repo, requested, _allowed_keys) do
    raise ArgumentError, "preloads must be a list, got: #{inspect(requested)}"
  end

  @spec preload([struct()], module(), [preload()], Enumerable.t(), term(), map(), map(), map()) :: [struct()]
  def preload(results, _repo, [], _allowed_keys, _authority, _policies, _options, _fields), do: results

  def preload(results, repo, requested, allowed_keys, authority, policies, options, fields)
      when is_list(requested) do
    validate_preloads!(requested, allowed_keys)

    requested = apply_preload_policies(results, requested, authority, policies, options, fields, repo)
    repo.preload(results, requested)
  end

  def preload(_results, _repo, requested, _allowed_keys, _authority, _policies, _options, _fields) do
    raise ArgumentError, "preloads must be a list, got: #{inspect(requested)}"
  end

  @doc """
  Raises when a preload request includes a key the resource did not declare.
  """
  @spec validate_preloads!([preload()], Enumerable.t()) :: :ok
  def validate_preloads!(requested, allowed_keys) when is_list(requested) do
    allowed_keys = MapSet.new(allowed_keys)

    unknown_keys =
      requested
      |> top_level_keys()
      |> Enum.reject(&MapSet.member?(allowed_keys, &1))
      |> Enum.sort()

    case unknown_keys do
      [] ->
        :ok

      [key] ->
        raise ArgumentError, "unknown reader preload #{inspect(key)}"

      keys ->
        inspected_keys = Enum.map_join(keys, ", ", &inspect/1)
        raise ArgumentError, "unknown reader preloads #{inspected_keys}"
    end
  end

  def validate_preloads!(requested, _allowed_keys) do
    raise ArgumentError, "preloads must be a list, got: #{inspect(requested)}"
  end

  @spec validate_preloads!([preload()], Enumerable.t(), module(), map()) :: :ok
  @doc false
  def validate_preloads!(requested, allowed_keys, root_schema, readers) when is_list(requested) do
    validate_preloads!(requested, allowed_keys)

    Enum.each(requested, fn
      key when is_atom(key) ->
        validate_preload_reader!(root_schema, key, readers)

      {key, nested} when is_atom(key) and is_list(nested) ->
        reader = validate_preload_reader!(root_schema, key, readers)
        association = fetch_association!(root_schema, key)

        validate_preloads!(
          nested,
          reader_preload_keys!(reader),
          association.related,
          reader_preload_readers(reader)
        )
    end)
  end

  def validate_preloads!(requested, _allowed_keys, _root_schema, _readers) do
    raise ArgumentError, "preloads must be a list, got: #{inspect(requested)}"
  end

  defp apply_preload_policies([], requested, _authority, _policies, _options, _fields, _repo),
    do: requested

  defp apply_preload_policies([first | _rest], requested, authority, policies, options, fields, repo)
       when is_struct(first) do
    Enum.map(requested, fn preload ->
      apply_preload_policy(first.__struct__, preload, authority, policies, options, fields, repo)
    end)
  end

  defp apply_preload_policy(root_schema, key, authority, readers, options, fields, repo)
       when is_atom(key) do
    reader = fetch_reader!(root_schema, key, readers)

    preload =
      association_preload(root_schema, key, reader, authority, Map.get(options, key, %{}), fields, repo)

    {key, preload}
  end

  defp apply_preload_policy(root_schema, {key, nested}, authority, readers, options, fields, repo)
       when is_atom(key) and is_list(nested) do
    reader = fetch_reader!(root_schema, key, readers)
    association = root_schema.__schema__(:association, key)
    nested = apply_nested_preload_policies(association.related, nested, authority, reader, fields, repo)

    preload =
      association_preload(root_schema, key, reader, authority, Map.get(options, key, %{}), fields, repo)

    {key, {preload, nested}}
  end

  defp apply_nested_preload_policies(_root_schema, [], _authority, _reader, _fields, _repo), do: []

  defp apply_nested_preload_policies(root_schema, nested, authority, reader, fields, repo) do
    allowed_keys = reader_preload_keys!(reader)
    readers = reader_preload_readers(reader)
    options = reader_preload_options(reader)

    validate_preloads!(nested, allowed_keys)

    Enum.map(nested, fn preload ->
      apply_preload_policy(root_schema, preload, authority, readers, options, fields, repo)
    end)
  end

  defp reader_preload_keys!(reader) do
    if Code.ensure_loaded?(reader) and function_exported?(reader, :preload_keys, 0) do
      reader.preload_keys()
    else
      raise ArgumentError,
            "reader #{inspect(reader)} must define preload_keys/0 for nested preloads"
    end
  end

  defp reader_preload_readers(reader) do
    if Code.ensure_loaded?(reader) and function_exported?(reader, :preload_readers, 0) do
      reader.preload_readers()
    else
      %{}
    end
  end

  defp reader_preload_options(reader) do
    if Code.ensure_loaded?(reader) and function_exported?(reader, :preload_options, 0) do
      reader.preload_options()
    else
      %{}
    end
  end

  defp validate_preload_reader!(root_schema, key, readers) do
    reader = fetch_reader!(root_schema, key, readers)
    validate_preload_association!(root_schema, key)
    validate_preload_query!(key, reader)
    reader
  end

  defp fetch_reader!(root_schema, key, readers) do
    with :error <- Map.fetch(readers, key),
         :error <- fetch_model_reader(root_schema, key) do
      raise ArgumentError,
            "reader preload #{inspect(key)} must declare a reader module on the reader or model association"
    else
      {:ok, reader} -> reader
    end
  end

  defp validate_preload_association!(root_schema, key) do
    fetch_association!(root_schema, key)
    :ok
  end

  defp fetch_association!(root_schema, key) do
    case root_schema.__schema__(:association, key) do
      nil ->
        raise ArgumentError,
              "reader preload #{inspect(key)} must reference an association on #{inspect(root_schema)}"

      association ->
        association
    end
  end

  defp validate_preload_query!(key, reader) do
    unless Code.ensure_loaded?(reader) and function_exported?(reader, :preload_query, 2) do
      raise ArgumentError,
            "reader preload #{inspect(key)} reader #{inspect(reader)} must define preload_query/2"
    end
  end

  defp fetch_model_reader(root_schema, key) do
    if Code.ensure_loaded?(root_schema) and
         function_exported?(root_schema, :__hawk_association_reader__, 1) do
      root_schema.__hawk_association_reader__(key)
    else
      :error
    end
  end

  defp association_preload(root_schema, key, reader, authority, %{limit: limit}, fields, repo) do
    association = root_schema.__schema__(:association, key)

    unless match?(%Ecto.Association.Has{cardinality: :many}, association) do
      raise ArgumentError,
            "bounded reader preload #{inspect(key)} must be a direct has_many association"
    end

    query = association_query(root_schema, key, reader, authority, %{})

    fn parent_ids ->
      ranking_query =
        query
        |> select([root: row], %{
          identity: field(row, ^Hawk.JsonApi.Schema.identity(association.related)),
          row_number:
            over(row_number(),
              partition_by: field(row, ^association.related_key),
              order_by: [asc: field(row, ^Hawk.JsonApi.Schema.identity(association.related))]
            )
        })

      identity = Hawk.JsonApi.Schema.identity(association.related)

      result_query =
        association.related
        |> from(as: :root)
        |> join(:inner, [root: row], ranking in subquery(ranking_query),
          on: field(row, ^identity) == ranking.identity and ranking.row_number <= ^limit
        )
        |> where([root: row], field(row, ^association.related_key) in ^parent_ids)

      result_query =
        case json_api_select_fields(association.related, authority, fields) do
          nil ->
            result_query

          selected ->
            required = association_required_fields(association)
            select(result_query, [root: row], struct(row, ^Enum.uniq(selected ++ required)))
        end

      repo.all(result_query)
    end
  end

  defp association_preload(root_schema, key, reader, authority, _options, fields, _repo),
    do: association_query(root_schema, key, reader, authority, fields)

  defp association_query(root_schema, key, reader, authority, fields) when is_atom(reader) do
    unless Code.ensure_loaded?(reader) and function_exported?(reader, :preload_query, 2) do
      raise ArgumentError,
            "reader preload #{inspect(key)} reader #{inspect(reader)} must define preload_query/2"
    end

    association = root_schema.__schema__(:association, key)

    query =
      association.related
      |> from(as: :root)
      |> reader.preload_query(authority)

    case json_api_select_fields(association.related, authority, fields) do
      nil ->
        query

      selected ->
        required = association_required_fields(association)
        select(query, [root: row], struct(row, ^Enum.uniq(selected ++ required)))
    end
  end

  defp association_required_fields(%{related_key: related_key}), do: [related_key]
  defp association_required_fields(_association), do: []

  defp json_api_select_fields(model, authority, fields) when map_size(fields) > 0 do
    resource = Hawk.Resource.Convention.resource_module(model)
    Code.ensure_compiled(resource)

    if function_exported?(resource, :json_api_select_fields, 2) do
      resource.json_api_select_fields(authority, fields)
    end
  end

  defp json_api_select_fields(_model, _authority, _fields), do: nil

  defp top_level_keys(requested) do
    Enum.map(requested, fn
      key when is_atom(key) ->
        key

      {key, nested} when is_atom(key) and is_list(nested) ->
        key

      preload ->
        raise ArgumentError, "invalid reader preload #{inspect(preload)}"
    end)
  end
end
