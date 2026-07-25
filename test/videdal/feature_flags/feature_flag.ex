defmodule Videdal.FeatureFlag do
  @moduledoc """
  ETS-backed read model for the Hawk non-Ecto pathfinder.

  Unlike Videdal's other models, this is a plain struct with no Ecto schema.
  It implements `Hawk.Schema` directly so Hawk's JSON:API machinery works
  without a database. Data lives in an ETS table populated by tests.
  """

  @behaviour Hawk.Schema

  defstruct [:id, :key, :enabled, :description]

  def __hawk_schema__(:fields), do: [:id, :key, :enabled, :description]
  def __hawk_schema__(:associations), do: []

  def __hawk_schema__(:type, :id), do: :binary_id
  def __hawk_schema__(:type, :key), do: :string
  def __hawk_schema__(:type, :enabled), do: :boolean
  def __hawk_schema__(:type, :description), do: :string
  def __hawk_schema__(:type, _), do: nil
  def __hawk_schema__(:association, _), do: nil

  def __hawk_resource__, do: Videdal.FeatureFlags
end
