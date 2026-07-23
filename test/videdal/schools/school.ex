defmodule Videdal.School do
  @moduledoc """
  School schema used by the Videdal example resources.
  """

  use Hawk.Model

  model "schools" do
    field(:name, :string)
  end
end
