defmodule Videdal.Announcements.ScopedTopics do
  @moduledoc """
  Example `Hawk.PubSub.TopicStrategy` isolating announcement broadcasts by
  school (tenant).

  This is the tenant-isolation escape hatch: a write at school A broadcasts to
  `hawk:announcements:school:<A>`, and a LiveView whose `mount` assigned
  `:current_school_id` subscribes to its own school's topic. Writes from other
  schools never reach it — no wasted re-query, no cross-tenant delivery.

  The broadcast side reads the tenant off the **model** (`model.school_id`);
  the subscribe side reads it off the **socket assigns**
  (`assigns[:current_school_id]`). Both sides live in this one module, so the
  app owns the lockstep and there is no two-sided Hawk split to drift.
  """

  @behaviour Hawk.PubSub.TopicStrategy

  @impl true
  def broadcast_topics(_resource, _operation, %Videdal.Announcement{school_id: school_id}) do
    ["hawk:announcements:school:#{school_id}"]
  end

  @impl true
  def subscribe_topics(_resource, assigns) do
    ["hawk:announcements:school:#{assigns[:current_school_id]}"]
  end
end
