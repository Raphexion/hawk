defmodule Videdal.Students.Reader do
  @moduledoc """
  Reader declaration module for the Videdal `Students` resource.

  The full reader DSL is not implemented yet, so this module exposes the pieces
  current Hawk tests need: known filter keys and policy-to-filter conversion.
  """

  alias Hawk.Reader, as: HawkReader
  alias Videdal.{Repo, Student}
  alias Videdal.Students.Policy

  @filter_keys MapSet.new([
                 :id,
                 :school_id,
                 :student_id,
                 :teacher_id,
                 :course_id,
                 :active,
                 :enrolled_on_or_after
               ])

  def filter_keys, do: @filter_keys
  def read_filter(authority), do: Policy.read_filter(authority)

  def one(opts), do: HawkReader.one(config(), opts)
  def one!(opts), do: HawkReader.one!(config(), opts)
  def all(opts), do: HawkReader.all(config(), opts)

  defp config do
    %{
      repo: Repo,
      schema: Student,
      filter_keys: filter_keys(),
      read_filter: &read_filter/1
    }
  end
end
