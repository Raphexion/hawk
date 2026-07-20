defmodule Videdal.LiveViews.CourseLive do
  @moduledoc """
  Default low-boilerplate LiveView example for the Videdal courses resource.

  `use Hawk.LiveView` generates index/show helpers, keyed form helpers, and the
  default `hawk:validate`, `hawk:save`, and `hawk:delete` event handlers.
  """

  use Hawk.LiveView,
    resource: Videdal.Courses
end

defmodule Videdal.LiveViews.CourseCustomSaveLive do
  @moduledoc """
  Override-friendly LiveView example for custom post-save behavior.

  `events: false` keeps generated helpers such as `hawk_validate/2` and
  `hawk_save/3`, but leaves `handle_event/3` to the application.
  """

  use Hawk.LiveView,
    resource: Videdal.Courses,
    events: false

  def handle_event("hawk:validate", params, socket), do: hawk_validate(params, socket)

  def handle_event("hawk:save", params, socket) do
    hawk_save(params, socket,
      on_success: fn socket, course ->
        Map.put(socket, :navigated_to, "/courses/#{course.id}")
      end
    )
  end
end
