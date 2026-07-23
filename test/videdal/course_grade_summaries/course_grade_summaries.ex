defmodule Videdal.CourseGradeSummaries do
  @moduledoc """
  Public facade for read-only course grade summaries.
  """

  alias Videdal.CourseGradeSummaries.{Reader, Writer}

  def one(opts), do: Reader.one(opts)
  def all(opts), do: Reader.all(opts)

  def create(attrs, authority), do: Writer.create(attrs, authority)
  def update(summary, attrs, authority), do: Writer.update(summary, attrs, authority)
  def delete(summary, authority), do: Writer.delete(summary, authority)
end
