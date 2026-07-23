defmodule Videdal.Teacher do
  @moduledoc """
  Teacher schema used by the Videdal example resources.
  """

  use Hawk.Model

  model "teachers" do
    field(:name, :string)

    belongs_to(:school, Videdal.School)
  end
end
