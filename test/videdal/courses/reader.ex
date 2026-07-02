defmodule Videdal.Courses.Reader do
  @moduledoc """
  Reader declaration module for the Videdal `Courses` resource.
  """

  alias Hawk.Reader, as: HawkReader
  alias Videdal.{Course, Repo}
  alias Videdal.Courses.Policy

  @filter_keys MapSet.new([:id, :school_id, :teacher_id])

  def filter_keys, do: @filter_keys
  def read_filter(authority), do: Policy.read_filter(authority)

  def one(opts), do: HawkReader.one(config(), opts)
  def one!(opts), do: HawkReader.one!(config(), opts)
  def all(opts), do: HawkReader.all(config(), opts)

  defp config do
    %{
      repo: Repo,
      schema: Course,
      filter_keys: filter_keys(),
      read_filter: &read_filter/1
    }
  end
end
