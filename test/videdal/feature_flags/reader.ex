defmodule Videdal.FeatureFlags.Reader do
  @moduledoc """
  ETS-backed reader for the FeatureFlags non-Ecto pathfinder.

  Reads directly from an ETS table instead of building an Ecto query.
  A real Ecto reader would use `use Hawk.Reader.Resource`; this one is
  hand-rolled because the model has no database source.
  """

  @table :feature_flags

  def all(_opts) do
    @table
    |> :ets.tab2list()
    |> Enum.map(fn {_id, flag} -> flag end)
  end

  def one(opts) do
    case Keyword.get(opts, :filter, %{}) do
      %{id: id} ->
        case :ets.lookup(@table, id) do
          [{_id, flag}] -> {:ok, flag}
          [] -> :not_found
        end

      _ ->
        :not_found
    end
  end

  def preload_keys, do: MapSet.new()
  def filter_keys, do: MapSet.new([:id])
  def filter_handlers, do: %{}
  def sort_keys, do: MapSet.new()
end
