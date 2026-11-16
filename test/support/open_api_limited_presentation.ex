defmodule Hawk.Test.OpenApiLimitedPresentation do
  @moduledoc false
  use Hawk.JsonApi.Resource

  type("course-entries")
  name("course entry")
  doc("A course entry in the Videdal catalog.")
  operations([:index, :show, :create, :delete, :action])
  attribute(:title, creatable: true)

  def adapter(Videdal.Course), do: __MODULE__
  def adapter(_model), do: nil
end
