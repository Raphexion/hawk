defmodule Videdal.Schools do
  @moduledoc """
  Public facade for the Videdal `Schools` resource.
  """

  alias Videdal.Schools.{Reader, Writer}

  def one(opts), do: Reader.one(opts)
  def all(opts), do: Reader.all(opts)

  def create(attrs, authority), do: Writer.create(attrs, authority)
  def update(school, attrs, authority), do: Writer.update(school, attrs, authority)
  def delete(school, authority), do: Writer.delete(school, authority)
end
