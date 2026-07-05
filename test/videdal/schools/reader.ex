defmodule Videdal.Schools.Reader do
  @moduledoc """
  Reader declaration module for the Videdal `Schools` resource.
  """

  alias Hawk.Reader, as: HawkReader
  alias Videdal.{Repo, School}
  alias Videdal.Schools.Policy

  @filter_keys MapSet.new([:id, :name])

  def filter_keys, do: @filter_keys
  def read_filter(authority), do: Policy.read_filter(authority)

  def one(opts), do: HawkReader.one(config(), opts)
  def one!(opts), do: HawkReader.one!(config(), opts)
  def all(opts), do: HawkReader.all(config(), opts)

  def preload_query(query, authority) do
    HawkReader.apply_authorized_filter(query, config(), authority)
  end

  defp config do
    %{
      repo: Repo,
      schema: School,
      filter_keys: filter_keys(),
      read_filter: &read_filter/1
    }
  end
end
