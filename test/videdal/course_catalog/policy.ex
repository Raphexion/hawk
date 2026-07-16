defmodule Videdal.CourseCatalog.Policy do
  @moduledoc false

  def read_filter(_authority), do: :all
end
