defmodule Videdal.Grade do
  @moduledoc """
  Grade schema used by the Videdal example resources.
  """

  use Ecto.Schema

  schema "grades" do
    field(:score, :integer)
    belongs_to(:school, Videdal.School)
    belongs_to(:student, Videdal.Student)
    belongs_to(:course, Videdal.Course)
  end
end
