defmodule Videdal.Students do
  @moduledoc """
  Public facade for the Videdal `Students` resource.

  This module is the stable entry point a host application would expose to the
  rest of its codebase. It delegates resource behavior to the reader and writer
  modules instead of implementing workflows inline.
  """

  alias Videdal.Students.{Reader, Writer}

  def one(opts), do: Reader.one(opts)
  def one!(opts), do: Reader.one!(opts)
  def all(opts), do: Reader.all(opts)

  def create(attrs, authority), do: Writer.create(attrs, authority)
  def update(student, attrs, authority), do: Writer.update(student, attrs, authority)
  def delete(student, authority), do: Writer.delete(student, authority)
end
