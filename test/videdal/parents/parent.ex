defmodule Videdal.Parent do
  @moduledoc """
  Parent schema used by the Videdal example resources.
  """

  use Hawk.Model

  model "parents" do
    field(:name, :string)
    belongs_to(:school, Videdal.School, policy: Videdal.Schools.Policy)
    has_many(:parent_students, Videdal.ParentStudent, policy: Videdal.Parents.Policy)
  end
end
