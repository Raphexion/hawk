defmodule Hawk.PubSub.TopicStrategy do
  @moduledoc """
  Behaviour for deriving the PubSub topics a Hawk write broadcasts to and a
  LiveView subscribes to.

  Hawk's default (`Hawk.PubSub.DefaultTopics`) publishes to a shared resource
  topic and a per-record instance topic. Host applications that need
  tenant/role/owner isolation implement this behaviour and configure it on the
  writer:

      use Hawk.Writer.Resource,
        model: MyApp.Grade,
        repo: MyApp.Repo,
        policy: MyApp.Grades.Policy,
        pubsub: {MyApp.PubSub, MyApp.PubSub.Topics}

  The two callbacks take different inputs on purpose: broadcast has the
  **record** (so it can read `model.school_id`), subscribe has the **viewer's
  socket assigns** (so it can read `assigns[:current_tenant_id]`). The
  application owns both sides and is responsible for keeping them in lockstep —
  if a broadcast topic and a subscribe topic do not match exactly, the message
  is silently lost. There is no Hawk-side enforcement; the escape hatch is
  app-owned by design, the same way the host owns its `Ecto.Repo`.

  ## Why two callbacks

  Subscribe is **routing**, not authorization. It picks which channel a screen
  joins from the screen's context (the socket assigns). Authorization happens
  later, in `Hawk.LiveView.refresh/3`, which re-queries through the socket's
  authority so the resource `read_filter/1` is never bypassed. Do not put
  authorization in `subscribe_topics/2`; put it in the refresh.

  ## Wiring it up

  Pass the strategy as the writer's `:topics` opt (defaults to
  `Hawk.PubSub.DefaultTopics`):

      use Hawk.Writer.Resource,
        model: MyApp.Grade,
        repo: MyApp.Repo,
        policy: MyApp.Grades.Policy,
        pubsub: MyApp.PubSub,
        topics: MyApp.PubSub.Topics

  ## Example — tenant isolation

      defmodule MyApp.PubSub.Topics do
        @behaviour Hawk.PubSub.TopicStrategy

        @impl true
        def broadcast_topics(_resource, _operation, model) do
          ["hawk:grades:school:\#{model.school_id}"]
        end

        @impl true
        def subscribe_topics(_resource, assigns) do
          ["hawk:grades:school:\#{assigns[:current_school_id]}"]
        end
      end

  A teacher at school A subscribes to `hawk:grades:school:<A>` and only
  receives writes from their own school. A principal (cross-tenant role) can
  subscribe to a different topic or the bare resource topic.
  """

  @doc """
  Returns the topics to broadcast a write to.

  Called from the writer's success path with the persisted `model`. Return one
  or more topic strings; `Hawk.PubSub.broadcast/5` publishes the same
  `Hawk.PubSub.Event` to each.
  """
  @callback broadcast_topics(resource :: module(), operation :: atom(), model :: struct()) :: [
              String.t()
            ]

  @doc """
  Returns the topics a LiveView should subscribe to for a resource.

  Called from `Hawk.LiveView.subscribe/2` with the resource and the socket's
  `assigns` (the screen's routing context — e.g. `assigns[:current_school_id]`,
  set in `mount`). Authorization is **not** done here; it happens in
  `Hawk.LiveView.refresh/3` through the socket's authority.
  """
  @callback subscribe_topics(resource :: module(), assigns :: map()) :: [String.t()]
end
