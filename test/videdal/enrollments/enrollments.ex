defmodule Videdal.Enrollments do
  @moduledoc """
  Public facade for the Videdal `Enrollments` resource.
  """

  alias Videdal.Enrollments.{Reader, Writer}

  def one(opts), do: Reader.one(opts)
  def all(opts), do: Reader.all(opts)

  def create(attrs, authority), do: Writer.create(attrs, authority)
  def update(enrollment, attrs, authority), do: Writer.update(enrollment, attrs, authority)
  def delete(enrollment, authority), do: Writer.delete(enrollment, authority)
end
