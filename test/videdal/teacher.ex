defmodule Videdal.Teacher do
  @moduledoc """
  A teacher belongs to one school and may teach many courses.
  """

  use Ecto.Schema

  schema "teachers" do
    field(:name, :string)
    belongs_to(:school, Videdal.School)
  end
end
