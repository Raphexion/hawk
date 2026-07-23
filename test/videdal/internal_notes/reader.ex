defmodule Videdal.InternalNotes.Reader do
  @moduledoc false

  def one(%{missing?: true}), do: :not_found
  def one(_opts), do: {:ok, %Videdal.InternalNote{}}

  def all(_opts), do: []
end
