defmodule Hawk.Reader.Preloader do
  @moduledoc """
  Applies explicitly allowed reader preloads after fetching rows.

  This is intentionally small: Hawk validates the requested top-level preload
  keys, then delegates batching to the host repo's `preload/2`. Resource modules
  own which associations are exposed as reader preloads.
  """
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

  @spec preload([struct()], module(), [preload()], Enumerable.t(), term(), map()) :: [struct()]
  def preload(results, _repo, [], _allowed_keys, _authority, _policies), do: results

  def preload(results, repo, requested, allowed_keys, authority, policies)
      when is_list(requested) do
    validate_preloads!(requested, allowed_keys)

    requested = apply_preload_policies(results, requested, authority, policies)
    repo.preload(results, requested)
  end

  def preload(_results, _repo, requested, _allowed_keys, _authority, _policies) do
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
  def validate_preloads!(requested, allowed_keys, root_schema, readers) when is_list(requested) do
    validate_preloads!(requested, allowed_keys)

    Enum.each(requested, fn
      key when is_atom(key) ->
        :ok

      {key, nested} when is_atom(key) and is_list(nested) ->
        reader = fetch_reader!(root_schema, key, readers)
        association = root_schema.__schema__(:association, key)

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

  defp apply_preload_policies([], requested, _authority, _policies), do: requested

  defp apply_preload_policies([first | _rest], requested, authority, policies)
       when is_struct(first) do
    Enum.map(requested, fn preload ->
      apply_preload_policy(first.__struct__, preload, authority, policies)
    end)
  end

  defp apply_preload_policy(root_schema, key, authority, readers) when is_atom(key) do
    reader = fetch_reader!(root_schema, key, readers)
    {key, association_query(root_schema, key, reader, authority)}
  end

  defp apply_preload_policy(root_schema, {key, nested}, authority, readers)
       when is_atom(key) and is_list(nested) do
    reader = fetch_reader!(root_schema, key, readers)
    association = root_schema.__schema__(:association, key)
    nested = apply_nested_preload_policies(association.related, nested, authority, reader)

    {key, {association_query(root_schema, key, reader, authority), nested}}
  end

  defp apply_nested_preload_policies(_root_schema, [], _authority, _reader), do: []

  defp apply_nested_preload_policies(root_schema, nested, authority, reader) do
    allowed_keys = reader_preload_keys!(reader)
    readers = reader_preload_readers(reader)

    validate_preloads!(nested, allowed_keys)

    Enum.map(nested, fn preload ->
      apply_preload_policy(root_schema, preload, authority, readers)
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

  defp fetch_reader!(root_schema, key, readers) do
    with :error <- Map.fetch(readers, key),
         :error <- fetch_model_reader(root_schema, key) do
      raise ArgumentError,
            "reader preload #{inspect(key)} must declare a reader module on the reader or model association"
    else
      {:ok, reader} -> reader
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

  defp association_query(root_schema, key, reader, authority) when is_atom(reader) do
    unless Code.ensure_loaded?(reader) and function_exported?(reader, :preload_query, 2) do
      raise ArgumentError,
            "reader preload #{inspect(key)} reader #{inspect(reader)} must define preload_query/2"
    end

    association = root_schema.__schema__(:association, key)
    query = from(association.related, as: :root)

    reader.preload_query(query, authority)
  end

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
