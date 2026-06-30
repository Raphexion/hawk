defmodule Videdal.School do
  @moduledoc """
  A school owns students, teachers, and courses in the Videdal example domain.
  """

  use Ecto.Schema

  schema "schools" do
    field(:name, :string)
  end
end
