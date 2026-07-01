defmodule Videdal.Teachers.Reader do
  @moduledoc """
  Reader declaration module for the Videdal `Teachers` resource.
  """

  alias Videdal.Teachers.Policy

  @filter_keys MapSet.new([:id, :school_id])

  def filter_keys, do: @filter_keys
  def read_filter(authority), do: Policy.read_filter(authority)

  def one(_opts), do: reader_runtime_not_implemented!()
  def one!(_opts), do: reader_runtime_not_implemented!()
  def all(_opts), do: reader_runtime_not_implemented!()

  defp reader_runtime_not_implemented! do
    raise "Videdal.Teachers.Reader will delegate to Hawk's reader runtime once it exists"
  end
end
