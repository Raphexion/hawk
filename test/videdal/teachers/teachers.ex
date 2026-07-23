defmodule Videdal.Teachers do
  @moduledoc """
  Public facade for the Videdal `Teachers` resource.
  """

  alias Videdal.Teachers.{Reader, Writer}

  def one(opts), do: Reader.one(opts)
  def all(opts), do: Reader.all(opts)

  def create(attrs, authority), do: Writer.create(attrs, authority)
  def update(teacher, attrs, authority), do: Writer.update(teacher, attrs, authority)
  def delete(teacher, authority), do: Writer.delete(teacher, authority)
end
