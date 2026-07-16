defmodule Videdal.InternalNotes.Reader do
  @moduledoc false

  def one(_opts), do: :not_found
  def one!(_opts), do: raise("not used")
  def all(_opts), do: []
end
