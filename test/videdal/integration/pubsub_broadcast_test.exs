defmodule Videdal.Integration.PubSubBroadcastTest do
  @moduledoc """
  Exercises Hawk.PubSub broadcast on create/update/delete.

  Serial (`async: false`) because every case subscribes to the shared
  `hawk:announcements` resource topic; running them concurrently would let one
  case's broadcast land in another's mailbox.
  """

  use Videdal.DatabaseCase, async: false

  alias Hawk.Authority
  alias Hawk.PubSub
  alias Videdal.{Announcement, Announcements}

  setup do
    :ok = PubSub.subscribe(Videdal.PubSub, Videdal.Announcements)
    :ok
  end

  test "create broadcasts a create event carrying the new identity" do
    assert {:ok, %Announcement{id: id}} =
             Announcements.create(%{body: "Grades are posted"}, Authority.system())

    assert_receive %PubSub.Event{
      resource: Videdal.Announcements,
      operation: :create,
      identity: :id,
      identity_value: ^id
    }
  end

  test "update broadcasts an update event for the same identity" do
    announcement = insert(:announcement, body: "Draft")
    id = announcement.id

    assert {:ok, %Announcement{body: "Final"}} =
             Announcements.update(announcement, %{body: "Final"}, Authority.system())

    assert_receive %PubSub.Event{
      resource: Videdal.Announcements,
      operation: :update,
      identity: :id,
      identity_value: ^id
    }
  end

  test "delete broadcasts a delete event for the removed identity" do
    announcement = insert(:announcement, body: "Stale")

    assert {:ok, %Announcement{}} = Announcements.delete(announcement, Authority.system())

    id = announcement.id

    assert_receive %PubSub.Event{
      resource: Videdal.Announcements,
      operation: :delete,
      identity: :id,
      identity_value: ^id
    }
  end

  test "an unauthorized write does not broadcast" do
    assert {:not_authorized, _} =
             Announcements.create(%{body: "should not persist"}, Authority.public())

    refute_received %PubSub.Event{}
  end

  test "a no-op update does not broadcast" do
    announcement = insert(:announcement, body: "Unchanged")

    assert {:ok, %Announcement{body: "Unchanged"}} =
             Announcements.update(announcement, %{}, Authority.system())

    refute_received %PubSub.Event{}
  end

  test "for_resource returns the writer's pubsub, or nil when undeclared" do
    assert PubSub.for_resource(Videdal.Announcements) == Videdal.PubSub
    # The InternalNotes writer did not declare :pubsub.
    assert PubSub.for_resource(Videdal.InternalNotes) == nil
  end

  test "topic derivation is stable and instance-scoped" do
    assert PubSub.topic(Videdal.Announcements) == "hawk:announcements"
    assert PubSub.topic(Videdal.Announcements, 42) == "hawk:announcements:42"
  end
end
