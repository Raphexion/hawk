defmodule Videdal.Course do
  @moduledoc """
  A course belongs to one school and has one teacher.
  """

  use Ecto.Schema

  schema "courses" do
    field(:title, :string)
    belongs_to(:school, Videdal.School)
    belongs_to(:teacher, Videdal.Teacher)
  end
end
