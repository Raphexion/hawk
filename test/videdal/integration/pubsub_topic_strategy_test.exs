defmodule Videdal.Integration.PubSubTopicStrategyTest do
  @moduledoc """
  Exercises the tenant-isolation escape hatch: an app `Hawk.PubSub.TopicStrategy`
  scopes topics by school, so a write at one school only reaches subscribers on
  that school's topic.

  Serial (`async: false`) so the manual topic subscriptions these cases open do
  not cross-pollute with the shared-topic suite.
  """

  use Videdal.DatabaseCase, async: false

  alias Hawk.{Authority, PubSub}
  alias Videdal.{Announcement, ScopedAnnouncements}

  setup do
    # Subscribers subscribe manually to the app-derived topics so the test can
    # observe exactly who receives what. The strategy's topic format is
    # `hawk:announcements:school:<school_id>`.
    :ok
  end

  defp subscribe_school(school_id) do
    :ok = Phoenix.PubSub.subscribe(Videdal.PubSub, "hawk:announcements:school:#{school_id}")
  end

  test "a write at school A reaches school A subscribers, not school B" do
    school_a = insert(:school)
    school_b = insert(:school)

    # Subscribe only to school A's topic.
    subscribe_school(school_a.id)

    # A write at school B must not reach a school A subscriber.
    assert {:ok, _} =
             ScopedAnnouncements.create(%{body: "B only", school_id: school_b.id}, Authority.system())

    refute_received %PubSub.Event{}

    # A write at school A does reach the school A subscriber.
    assert {:ok, %Announcement{} = announcement} =
             ScopedAnnouncements.create(
               %{body: "A only", school_id: school_a.id},
               Authority.system()
             )

    id = announcement.id

    assert_receive %PubSub.Event{
      resource: Videdal.ScopedAnnouncements,
      operation: :create,
      identity_value: ^id
    }
  end

  test "update and delete are scoped the same way" do
    school_a = insert(:school)
    school_b = insert(:school)

    {:ok, a_announcement} =
      ScopedAnnouncements.create(%{body: "A", school_id: school_a.id}, Authority.system())

    {:ok, b_announcement} =
      ScopedAnnouncements.create(%{body: "B", school_id: school_b.id}, Authority.system())

    # Subscribe only to school A's topic. The test process must not receive
    # anything broadcast on school B's topic.
    subscribe_school(school_a.id)

    assert {:ok, _} = ScopedAnnouncements.update(a_announcement, %{body: "A2"}, Authority.system())
    assert {:ok, _} = ScopedAnnouncements.delete(b_announcement, Authority.system())

    a_announcement_id = a_announcement.id

    # School A subscriber receives its own update.
    assert_receive %PubSub.Event{
      resource: Videdal.ScopedAnnouncements,
      operation: :update,
      identity_value: ^a_announcement_id
    }

    # School B's delete was broadcast on school B's topic; school A subscriber
    # never sees it.
    refute_received %PubSub.Event{operation: :delete}
  end

  test "config_for_resource exposes the configured topic strategy" do
    assert %{pubsub: Videdal.PubSub, topic_strategy: Videdal.Announcements.ScopedTopics} =
             PubSub.config_for_resource(Videdal.ScopedAnnouncements)

    # The default (bare) writer falls back to Hawk.PubSub.DefaultTopics.
    assert %{pubsub: Videdal.PubSub, topic_strategy: Hawk.PubSub.DefaultTopics} =
             PubSub.config_for_resource(Videdal.Announcements)
  end
end
