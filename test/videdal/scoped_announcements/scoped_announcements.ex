defmodule Videdal.ScopedAnnouncements do
  @moduledoc """
  Facade for the tenant-isolated announcements demo.

  Its writer declares `pubsub: Videdal.PubSub, topics:
  Videdal.Announcements.ScopedTopics`, so a write at one school broadcasts only
  to that school's topic and a LiveView subscribed to its own school never
  receives another school's writes. See `Hawk.PubSub.TopicStrategy`.
  """

  use Hawk.Resource,
    model: Videdal.Announcement
end
