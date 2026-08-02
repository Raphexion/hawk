defmodule Videdal.LiveViews.AnnouncementLiveTest do
  @moduledoc """
  Drives the real-time LiveView refresh path against the announcements
  resource: subscribe, trigger a writer broadcast, and call
  `Hawk.LiveView.refresh/3` exactly as a `handle_info/2` clause would.

  Serial (`async: false`) so broadcasts from these cases do not cross-pollinate
  with `PubSubBroadcastTest` on the shared `hawk:announcements` topic.
  """

  use Videdal.DatabaseCase, async: false

  import Hawk.TestSocket, only: [socket: 0]

  alias Hawk.{Authority, LiveView, PubSub}
  alias Videdal.{Announcement, Announcements}
  alias Videdal.LiveViews.AnnouncementLive

  test "an index screen refreshes when another writer creates a record" do
    insert(:announcement, body: "first")

    socket =
      socket()
      |> AnnouncementLive.assign_index(Authority.system())
      |> LiveView.subscribe(Videdal.Announcements)

    assert length(socket.assigns.announcements) == 1

    assert {:ok, %Announcement{body: "second"}} =
             Announcements.create(%{body: "second"}, Authority.system())

    assert_receive %PubSub.Event{resource: Videdal.Announcements, operation: :create}

    socket = LiveView.refresh(socket, Videdal.Announcements, authority: Authority.system())

    bodies = Enum.map(socket.assigns.announcements, & &1.body)
    assert "second" in bodies
    assert length(socket.assigns.announcements) == 2
  end

  test "a show screen refreshes when another writer updates its record" do
    announcement = insert(:announcement, body: "draft")

    socket =
      socket()
      |> AnnouncementLive.assign_show(Authority.system(), announcement.id)
      |> LiveView.subscribe(Videdal.Announcements)

    assert socket.assigns.announcement.body == "draft"

    assert {:ok, %Announcement{}} =
             Announcements.update(announcement, %{body: "final"}, Authority.system())

    assert_receive %PubSub.Event{resource: Videdal.Announcements, operation: :update}

    socket = LiveView.refresh(socket, Videdal.Announcements, authority: Authority.system())

    assert socket.assigns.announcement.body == "final"
  end

  test "a show screen degrades to not-found when another writer deletes its record" do
    announcement = insert(:announcement, body: "gone soon")

    socket =
      socket()
      |> AnnouncementLive.assign_show(Authority.system(), announcement.id)
      |> LiveView.subscribe(Videdal.Announcements)

    assert {:ok, %Announcement{}} = Announcements.delete(announcement, Authority.system())

    assert_receive %PubSub.Event{resource: Videdal.Announcements, operation: :delete}

    socket = LiveView.refresh(socket, Videdal.Announcements, authority: Authority.system())

    assert Map.has_key?(socket.assigns, :hawk_error)
  end
end
