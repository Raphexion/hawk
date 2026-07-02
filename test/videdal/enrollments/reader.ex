defmodule Videdal.Enrollments.Reader do
  @moduledoc """
  Reader declaration module for the Videdal `Enrollments` resource.
  """

  alias Hawk.Reader, as: HawkReader
  alias Videdal.{Enrollment, Repo}
  alias Videdal.Enrollments.Policy

  @filter_keys MapSet.new([:id, :school_id, :student_id, :course_id])

  def filter_keys, do: @filter_keys
  def read_filter(authority), do: Policy.read_filter(authority)

  def one(opts), do: HawkReader.one(config(), opts)
  def one!(opts), do: HawkReader.one!(config(), opts)
  def all(opts), do: HawkReader.all(config(), opts)

  defp config do
    %{
      repo: Repo,
      schema: Enrollment,
      filter_keys: filter_keys(),
      read_filter: &read_filter/1
    }
  end
end
