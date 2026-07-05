defmodule Hawk.Reader.Preloader do
  @moduledoc """
  Applies explicitly allowed reader preloads after fetching rows.

  This is intentionally small: Hawk validates the requested top-level preload
  keys, then delegates batching to the host repo's `preload/2`. Resource modules
  own which associations are exposed as reader preloads.
  """

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
