defmodule Videdal.LiveViews.AnnouncementLive do
  @moduledoc """
  Low-boilerplate LiveView for the Videdal announcements resource, used by the
  real-time refresh test.

  `use Hawk.LiveView` generates the index/show/form helpers and the default
  `hawk:validate`, `hawk:save`, and `hawk:delete` event handlers. The test
  drives the PubSub side directly: it subscribes the process, triggers a write,
  and calls `Hawk.LiveView.refresh/3` from a `handle_info`-style path.
  """

  use Hawk.LiveView,
    resource: Videdal.Announcements
end
