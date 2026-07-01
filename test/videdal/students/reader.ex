defmodule Videdal.Students.Reader do
  @moduledoc """
  Reader declaration module for the Videdal `Students` resource.

  The full reader DSL is not implemented yet, so this module exposes the pieces
  current Hawk tests need: known filter keys and policy-to-filter conversion.
  """

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

  def one(_opts), do: reader_runtime_not_implemented!()
  def one!(_opts), do: reader_runtime_not_implemented!()
  def all(_opts), do: reader_runtime_not_implemented!()

  defp reader_runtime_not_implemented! do
    raise "Videdal.Students.Reader will delegate to Hawk's reader runtime once it exists"
  end
end
