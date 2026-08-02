defmodule Videdal.ScopedAnnouncements.Writer do
  @moduledoc """
  Writer for the scoped announcements resource — the tenant-isolation demo.

  The `:topics` opt (`Videdal.Announcements.ScopedTopics`) routes broadcasts
  through the app's topic strategy instead of the default, so a write at one
  school only reaches subscribers on that school's topic.
  """

  use Hawk.Writer.Resource,
    model: Videdal.Announcement,
    repo: Videdal.Repo,
    policy: Videdal.ScopedAnnouncements.Policy,
    pubsub: Videdal.PubSub,
    topics: Videdal.Announcements.ScopedTopics

  create do
    cast([:body, :school_id])
    validate_required([:body])
  end

  update do
    cast([:body, :school_id])
  end

  delete(:default)
end
