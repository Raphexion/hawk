defmodule Hawk.PubSub.DefaultTopics do
  @moduledoc """
  The built-in `Hawk.PubSub.TopicStrategy`, used when a writer declares
  `:pubsub` without a strategy (the bare `pubsub: MyApp.PubSub` form).

  Broadcasts every write to the resource topic and the instance topic; a
  LiveView subscribes to the resource topic only. This reproduces the original
  Hawk PubSub behavior and is the right default for single-tenant surfaces and
  for cross-tenant roles that want every write.

  For tenant/owner isolation, implement `Hawk.PubSub.TopicStrategy` and pass it
  as the tuple form (`pubsub: {MyApp.PubSub, MyApp.PubSub.Topics}`).
  """

  @behaviour Hawk.PubSub.TopicStrategy

  @impl true
  def broadcast_topics(resource, _operation, model) do
    identity = resource.__hawk_resource__(:identity)
    identity_value = Map.get(model, identity)

    [Hawk.PubSub.topic(resource), Hawk.PubSub.topic(resource, identity_value)]
  end

  @impl true
  def subscribe_topics(resource, _assigns) do
    [Hawk.PubSub.topic(resource)]
  end
end
