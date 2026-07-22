defmodule Videdal.CourseCatalog.Reader do
  @moduledoc false

  def one(%{missing?: true}), do: :not_found
  def one(_opts), do: {:ok, %Videdal.Course{}}

  def one!(opts) do
    case one(opts) do
      {:ok, course} -> course
      :not_found -> raise "expected one result, got none"
    end
  end

  def all(_opts), do: []
end
