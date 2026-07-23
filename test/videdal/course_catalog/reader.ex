defmodule Videdal.CourseCatalog.Reader do
  @moduledoc false

  def one(%{missing?: true}), do: :not_found
  def one(_opts), do: {:ok, %Videdal.Course{}}

  def all(_opts), do: []
end
