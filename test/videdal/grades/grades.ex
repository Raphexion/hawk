defmodule Videdal.Grades do
  @moduledoc """
  Public facade for the Videdal `Grades` resource.
  """

  alias Videdal.Grades.{Reader, Writer}

  def one(opts), do: Reader.one(opts)
  def one!(opts), do: Reader.one!(opts)
  def all(opts), do: Reader.all(opts)

  def create(attrs, authority), do: Writer.create(attrs, authority)
  def update(grade, attrs, authority), do: Writer.update(grade, attrs, authority)
  def delete(grade, authority), do: Writer.delete(grade, authority)
end
