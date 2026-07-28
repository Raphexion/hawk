defmodule Videdal.LiveViews.CourseLive do
  @moduledoc """
  Default low-boilerplate LiveView example for the Videdal courses resource.

  `use Hawk.LiveView` generates index/show helpers, keyed form helpers, and the
  default `hawk:validate`, `hawk:save`, and `hawk:delete` event handlers.
  """

  use Hawk.LiveView,
    resource: Videdal.Courses
end
