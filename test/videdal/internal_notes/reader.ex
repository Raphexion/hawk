defmodule Videdal.InternalNotes.Reader do
  @moduledoc false

  def one(%{missing?: true}), do: :not_found
  def one(_opts), do: {:ok, %Videdal.InternalNote{}}

  def one!(opts) do
    case one(opts) do
      {:ok, note} -> note
      :not_found -> raise "expected one result, got none"
    end
  end

  def all(_opts), do: []
end
