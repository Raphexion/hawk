defmodule Videdal.Announcement do
  @moduledoc """
  Schema for the Videdal `Announcements` resource.

  Announcements exist to exercise Hawk's real-time (PubSub) layer in
  isolation: the writer declares `pubsub: Videdal.PubSub`, so every
  create/update/delete broadcasts a `Hawk.PubSub.Event`. The resource is
  intentionally minimal — one field, no associations — so the real-time tests
  stay self-contained.
  """

  use Hawk.Model

  model "announcements" do
    field(:body, :string)
    field(:school_id, :binary_id)
  end
end
