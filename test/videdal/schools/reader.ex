defmodule Videdal.Schools.Reader do
  @moduledoc """
  Reader declaration module for the Videdal `Schools` resource.
  """

  alias Videdal.Schools.Policy

  @filter_keys MapSet.new([:id, :name])

  def filter_keys, do: @filter_keys
  def read_filter(authority), do: Policy.read_filter(authority)

  def one(_opts), do: reader_runtime_not_implemented!()
  def one!(_opts), do: reader_runtime_not_implemented!()
  def all(_opts), do: reader_runtime_not_implemented!()

  defp reader_runtime_not_implemented! do
    raise "Videdal.Schools.Reader will delegate to Hawk's reader runtime once it exists"
  end
end
