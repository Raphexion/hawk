defmodule Videdal.CourseGradeSummaries.Policy do
  @moduledoc """
  Policy for read-only grade summary views.
  """

  alias Hawk.MutationContext

  def read_filter(_authority), do: :all

  def create?(%MutationContext{}), do: false
  def update?(%MutationContext{}), do: false
  def delete?(%MutationContext{}), do: false
end
