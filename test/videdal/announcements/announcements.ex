defmodule Videdal.Announcements do
  @moduledoc """
  Public facade for the Videdal `Announcements` resource.

  The minimal resource backing the real-time demo: its writer declares
  `pubsub: Videdal.PubSub`, so writes broadcast `Hawk.PubSub.Event` and a
  LiveView can subscribe and refresh without reloading. See
  `Hawk.PubSub` and `Hawk.LiveView.subscribe/2`.
  """

  use Hawk.Resource,
    model: Videdal.Announcement
end
