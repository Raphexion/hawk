defmodule Videdal.Teachers.Reader do
  @moduledoc """
  Reader declaration module for the Videdal `Teachers` resource.
  """

  alias Hawk.Reader, as: HawkReader
  alias Videdal.{Repo, Teacher}
  alias Videdal.Teachers.Policy

  @filter_keys MapSet.new([:id, :school_id])

  def filter_keys, do: @filter_keys
  def read_filter(authority), do: Policy.read_filter(authority)

  def one(opts), do: HawkReader.one(config(), opts)
  def one!(opts), do: HawkReader.one!(config(), opts)
  def all(opts), do: HawkReader.all(config(), opts)

  defp config do
    %{
      repo: Repo,
      schema: Teacher,
      filter_keys: filter_keys(),
      read_filter: &read_filter/1
    }
  end
end
