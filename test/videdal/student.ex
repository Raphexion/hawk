defmodule Videdal.Student do
  @moduledoc """
  A student belongs to one school and can be enrolled in courses.
  """

  use Ecto.Schema

  schema "students" do
    field(:name, :string)
    field(:active, :boolean, default: true)
    belongs_to(:school, Videdal.School)
  end
end
