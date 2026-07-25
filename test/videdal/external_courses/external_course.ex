defmodule Videdal.ExternalCourse do
  @moduledoc """
  Course schema used by adapter-contract tests.
  """

  use Hawk.Model

  model "external_courses" do
    field(:title, :string)
    field(:public_slug, :string)

    belongs_to(:teacher, Videdal.Teacher)
  end
end
