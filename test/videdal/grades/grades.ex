defmodule Videdal.Grades do
  @moduledoc """
  Public facade for the Videdal `Grades` resource.
  """

  alias Videdal.Grades.Reader

  def one(opts), do: Reader.one(opts)
  def one!(opts), do: Reader.one!(opts)
  def all(opts), do: Reader.all(opts)
end
