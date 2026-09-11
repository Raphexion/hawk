defmodule Videdal.Courses.BusinessJsonApi do
  @moduledoc false
  use Hawk.JsonApi.Alias, resource: Videdal.Courses, alias: :business

  type("modules")
end
