defmodule Videdal.Course do
  @moduledoc """
  Course schema used by the Videdal example resources.
  """

  use Hawk.Model

  model "courses" do
    field(:title, :string)

    belongs_to(:school, Videdal.School)
    belongs_to(:teacher, Videdal.Teacher)
    has_many(:grades, Videdal.Grade)
  end
end
