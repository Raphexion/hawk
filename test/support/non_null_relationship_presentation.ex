defmodule Hawk.Test.NonNullRelationshipPresentation do
  @moduledoc false
  use Hawk.JsonApi.Resource

  type("courses")
  relationship(:campus, source: :school, writable: true, required: :create, nullable: false)
  relationship(:teacher, writable: true, nullable: true)

  def adapter(Videdal.Course), do: __MODULE__
  def adapter(_model), do: nil
end
