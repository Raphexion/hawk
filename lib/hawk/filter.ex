defmodule Hawk.Filter do
  import Kernel, except: [and: 2, or: 2]

  @moduledoc """
  Small filter AST used by reader policies and caller-provided filters.

  This module intentionally stops at AST normalization and composition. Turning
  the AST into Ecto queries belongs to the reader/compiler layer.
  """

  @type key :: atom()
  @type scalar :: term()

  @type value ::
          scalar()
          | nil
          | {:eq, scalar() | nil}
          | {:neq, scalar() | nil}
          | {:in, [scalar()]}
          | {:not_in, [scalar()]}
          | {:lt, scalar()}
          | {:lte, scalar()}
          | {:gt, scalar()}
          | {:gte, scalar()}
          | {:like, String.t()}
          | {:ilike, String.t()}
          | {:near, map()}

  @type t ::
          :all
          | :none
          | %{required(key()) => value()}
          | {:and, t(), t()}
          | {:or, t(), t()}

  @operators [:eq, :neq, :in, :not_in, :lt, :lte, :gt, :gte, :like, :ilike, :near]

  @doc """
  Normalizes map shorthand into explicit equality values.

  A bare map value, including `nil`, becomes `{:eq, value}`. Explicit operator
  tuples are preserved.
  """
  @spec normalize(t()) :: t()
  def normalize(:all), do: :all
  def normalize(:none), do: :none

  def normalize({:and, left, right}) do
    {:and, normalize(left), normalize(right)}
  end

  def normalize({:or, left, right}) do
    {:or, normalize(left), normalize(right)}
  end

  def normalize(filter) when is_map(filter) do
    Map.new(filter, fn
      {key, value} when is_atom(key) -> {key, normalize_value(value)}
      {key, _value} -> raise ArgumentError, "filter keys must be atoms, got: #{inspect(key)}"
    end)
  end

  def normalize(filter) do
    raise ArgumentError, "invalid filter AST: #{inspect(filter)}"
  end

  @doc """
  Combines two filters with logical `AND`.
  """
  @spec unquote(:and)(t(), t()) :: t()
  def unquote(:and)(left, right) do
    left = normalize(left)
    right = normalize(right)

    case {left, right} do
      {:none, _right} -> :none
      {_left, :none} -> :none
      {:all, right} -> right
      {left, :all} -> left
      {left, right} -> combine_and(left, right)
    end
  end

  @doc """
  Combines two filters with logical `OR`.
  """
  @spec unquote(:or)(t(), t()) :: t()
  def unquote(:or)(left, right) do
    left = normalize(left)
    right = normalize(right)

    case {left, right} do
      {:all, _right} -> :all
      {_left, :all} -> :all
      {:none, right} -> right
      {left, :none} -> left
      {left, right} -> {:or, left, right}
    end
  end

  @doc """
  Extracts every filter key from a filter AST.
  """
  @spec keys(t()) :: MapSet.t(key())
  def keys(filter) do
    filter
    |> normalize()
    |> do_keys()
  end

  @doc """
  Raises when a filter contains keys outside the provided known-key set.
  """
  @spec validate_keys!(t(), Enumerable.t()) :: :ok
  def validate_keys!(filter, known_keys) do
    known_keys = MapSet.new(known_keys)

    unknown_keys =
      filter
      |> keys()
      |> Enum.reject(&MapSet.member?(known_keys, &1))
      |> Enum.sort()

    case unknown_keys do
      [] ->
        :ok

      [key] ->
        raise ArgumentError, "unknown filter key #{inspect(key)}"

      keys ->
        inspected_keys = Enum.map_join(keys, ", ", &inspect/1)
        raise ArgumentError, "unknown filter keys #{inspected_keys}"
    end
  end

  defp normalize_value({operator, _value} = value) when operator in @operators, do: value
  defp normalize_value(value), do: {:eq, value}

  defp combine_and(left, right) when is_map(left) do
    if is_map(right), do: merge_maps(left, right), else: {:and, left, right}
  end

  defp combine_and(left, right), do: {:and, left, right}

  defp merge_maps(left, right) do
    Enum.reduce_while(right, left, fn {key, right_value}, acc ->
      case Map.fetch(acc, key) do
        {:ok, left_value} when left_value != right_value -> {:halt, :none}
        {:ok, _left_value} -> {:cont, acc}
        :error -> {:cont, Map.put(acc, key, right_value)}
      end
    end)
  end

  defp do_keys(:all), do: MapSet.new()
  defp do_keys(:none), do: MapSet.new()

  defp do_keys({operator, left, right}) when operator in [:and, :or] do
    MapSet.union(do_keys(left), do_keys(right))
  end

  defp do_keys(filter) when is_map(filter) do
    filter
    |> Map.keys()
    |> MapSet.new()
  end
end
