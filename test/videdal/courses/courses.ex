defmodule Videdal.Courses do
  @moduledoc """
  Public facade for the Videdal `Courses` resource.
  """

  alias Videdal.Courses.{Reader, Writer}

  def one(opts), do: Reader.one(opts)
  def one!(opts), do: Reader.one!(opts)
  def all(opts), do: Reader.all(opts)

  def create(attrs, authority), do: Writer.create(attrs, authority)
  def update(course, attrs, authority), do: Writer.update(course, attrs, authority)
  def delete(course, authority), do: Writer.delete(course, authority)
end
