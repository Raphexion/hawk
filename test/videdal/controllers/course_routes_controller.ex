defmodule Videdal.Controllers.CourseRoutesController do
  @moduledoc false

  use Hawk.JsonApi.Controller,
    resource: Videdal.Courses
end
