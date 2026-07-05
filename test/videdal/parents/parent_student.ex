defmodule Videdal.ParentStudent do
  @moduledoc """
  Join schema connecting parents to students in the Videdal example.
  """

  use Hawk.Model

  model "parent_students" do
    belongs_to(:parent, Videdal.Parent, policy: Videdal.Parents.Policy)
    belongs_to(:student, Videdal.Student, policy: Videdal.Students.Policy)
    belongs_to(:school, Videdal.School, policy: Videdal.Schools.Policy)
  end
end
