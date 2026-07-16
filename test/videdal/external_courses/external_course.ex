defmodule Videdal.ExternalCourse do
  @moduledoc """
  Course schema used by adapter-contract tests.

  The model-level JSON:API contract intentionally differs from the resource
  adapter contract so tests exercise facade adapter metadata instead of falling
  back to schema metadata.
  """

  use Hawk.Model

  model "external_courses" do
    field(:title, :string)
    field(:public_slug, :string)

    belongs_to(:teacher, Videdal.ExternalTeacher)
  end

  json_api do
    type("internal_courses")
    attributes([:title, :public_slug])
    relationships([:teacher])
  end
end
