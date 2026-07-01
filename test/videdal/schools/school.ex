defmodule Videdal.School do
  @moduledoc """
  School schema used by the Videdal example resources.
  """

  use Ecto.Schema

  schema "schools" do
    field(:name, :string)
  end
end
