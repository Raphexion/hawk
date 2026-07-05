defmodule Hawk.Reader.Preloader do
  import Ecto.Query

  @moduledoc """
  Applies explicitly allowed reader preloads after fetching rows.

  This is intentionally small: Hawk validates the requested top-level preload
  keys, then delegates batching to the host repo's `preload/2`. Resource modules
  own which associations are exposed as reader preloads.
  """

  alias Hawk.Reader.FilterCompiler

  @type preload :: atom() | {atom(), [preload()]}

  @doc """
  Preloads requested associations through the host repo.

  Empty preload requests are a no-op. Unknown top-level preload keys fail loudly
  before the repo is called.
  """
  @spec preload([struct()], module(), [preload()], Enumerable.t()) :: [struct()]
  def preload(results, repo, requested, allowed_keys) do
    preload(results, repo, requested, allowed_keys, nil, %{})
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

  defp apply_preload_policies([], requested, _authority, _policies), do: requested

  defp apply_preload_policies([first | _rest], requested, authority, policies)
       when is_struct(first) do
    Enum.map(requested, fn preload ->
      apply_preload_policy(first.__struct__, preload, authority, policies)
    end)
  end

  defp apply_preload_policy(root_schema, key, authority, policies) when is_atom(key) do
    case Map.fetch(policies, key) do
      {:ok, policy} -> {key, association_query(root_schema, key, policy, authority)}
      :error -> key
    end
  end

  defp apply_preload_policy(root_schema, {key, nested}, authority, policies)
       when is_atom(key) and is_list(nested) do
    case Map.fetch(policies, key) do
      {:ok, policy} -> {key, {association_query(root_schema, key, policy, authority), nested}}
      :error -> {key, nested}
    end
  end

  defp association_query(root_schema, key, policy, authority) when is_atom(policy) do
    unless Code.ensure_loaded?(policy) and function_exported?(policy, :read_filter, 1) do
      raise ArgumentError,
            "reader preload #{inspect(key)} policy #{inspect(policy)} must define read_filter/1"
    end

    association = root_schema.__schema__(:association, key)
    schema = association.related

    query = from(schema, as: :root)

    if function_exported?(policy, :preload_query, 2) do
      policy.preload_query(query, authority)
    else
      FilterCompiler.compile(query, schema, policy.read_filter(authority), %{})
    end
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
