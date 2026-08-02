defmodule Videdal.LiveViews.ScopedAnnouncementLiveTest do
  @moduledoc """
  Drives the tenant-isolated LiveView refresh end-to-end: `mount` assigns the
  school id (the routing context), `Hawk.LiveView.subscribe/2` asks the writer's
  topic strategy for the topics from `assigns`, and `refresh/3` re-queries
  through the socket's authority.

  Proves a school A index never refreshes from a school B write.
  """

  use Videdal.DatabaseCase, async: false

  import Hawk.TestSocket, only: [socket: 0]

  alias Hawk.{Authority, LiveView, PubSub}
  alias Videdal.ScopedAnnouncements
  alias Videdal.LiveViews.ScopedAnnouncementLive

  test "a school A index refreshes from its own write, not a school B write" do
    school_a = insert(:school)
    school_b = insert(:school)

    socket =
      socket()
      |> Phoenix.Component.assign(:current_school_id, school_a.id)
      |> Phoenix.Component.assign(:hawk_authority, Authority.system())
      |> ScopedAnnouncementLive.assign_index(Authority.system())
      |> LiveView.subscribe(ScopedAnnouncements)

    assert socket.assigns.announcements == []

    # A school B write broadcasts on school B's topic; the school A subscriber
    # never receives it, so no refresh fires and the index stays empty.
    assert {:ok, _} =
             ScopedAnnouncements.create(%{body: "school B", school_id: school_b.id}, Authority.system())

    refute_received %PubSub.Event{}

    # A school A write reaches the school A subscriber; refresh re-queries
    # through the socket's authority and the new row appears.
    assert {:ok, _} =
             ScopedAnnouncements.create(%{body: "school A", school_id: school_a.id}, Authority.system())

    assert_receive %PubSub.Event{resource: Videdal.ScopedAnnouncements, operation: :create}

    socket = LiveView.refresh(socket, ScopedAnnouncements, authority: Authority.system())

    bodies = Enum.map(socket.assigns.announcements, & &1.body)
    assert "school A" in bodies
  end
end
