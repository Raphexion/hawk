defmodule Videdal.Course do
  @moduledoc """
  Course schema used by the Videdal example resources.
  """

  use Ecto.Schema

  schema "courses" do
    field(:title, :string)
    belongs_to(:school, Videdal.School)
    belongs_to(:teacher, Videdal.Teacher)
    has_many(:grades, Videdal.Grade)
  end
end
