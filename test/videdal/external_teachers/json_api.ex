defmodule Videdal.ExternalTeachers.JsonApi do
  @moduledoc false

  use Hawk.JsonApi.Resource

  type("internal_teachers")
  attribute(:name, [])
end
