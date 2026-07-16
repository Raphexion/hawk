defmodule Videdal.CourseCatalog.JsonApi do
  @moduledoc false

  use Hawk.JsonApi.Resource

  type("course-catalog")

  attribute(:title, [])
  relationship(:teacher, [])
end
