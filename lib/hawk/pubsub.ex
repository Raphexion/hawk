defmodule Hawk.PubSub do
  @moduledoc """
  Hawk's optional real-time notification layer over the host application's
  `Phoenix.PubSub`.

  Hawk does **not** start or supervise a PubSub. The host application owns its
  `Phoenix.PubSub` (e.g. `MyApp.PubSub`) the same way it owns its `Ecto.Repo`,
  authentication, and supervision tree. This module owns the Hawk conventions:
  stable topic derivation, the change event, and the broadcast/subscribe
  helpers that keep LiveView refresh on the policy-gated read path.

  ## Opting in

  Declare `:pubsub` on the writer. Every successful `create/update/delete`
  through that writer publishes a `Hawk.PubSub.Event`.

  The `:topics` opt is optional and defaults to `Hawk.PubSub.DefaultTopics`:

      # single-tenant / cross-tenant-everything — shared resource + instance topics
      pubsub: MyApp.PubSub

      # tenant isolation — app-owned topic strategy
      pubsub: MyApp.PubSub,
      topics: MyApp.PubSub.Topics

  Resources without `:pubsub` never broadcast and pay nothing.

  ## What is broadcast

  A `Hawk.PubSub.Event` — *not* the model. Each subscriber re-queries through
  its **own** authority, so the resource's read policy (`read_filter/1`) is
  never bypassed. The writer's view of the record is never pushed to readers.

  ## Topics

    * Resource topic — `topic/1` — every create/update/delete for the resource.
    * Instance topic — `topic/2` — changes to one record (by identity value).

  `broadcast/4` publishes to both on every write, so a subscriber to the
  resource topic sees all changes. Subscribe to the instance topic for a show
  screen that wants fewer messages.

  ## LiveView integration

  `Hawk.LiveView.subscribe/2` reads the writer's `:pubsub` from the resource,
  subscribes the LiveView process to the resource topic, and `Hawk.LiveView.refresh/3`
  re-runs the current index or show assign through the socket's authority. See
  those helpers for the one-line hook.

  ## Authority and existence visibility — a caveat

  The resource topic is shared: every subscriber learns *that* a write
  occurred and receives the changed record's identity value, even when the
  subscriber's `read_filter/1` would hide that record from them. The visible
  **data** never leaks — a subscriber whose authority hides the record
  re-queries and simply does not see it — but the **event metadata** (a write
  happened, plus an opaque id) is observable to everyone on the topic.

  For an internal admin surface this is the standard PubSub tradeoff and is
  usually fine. When the *existence* of records must stay secret across
  authorities (for example, one tenant must not learn that another tenant wrote
  anything), do not put those authorities on the same shared resource topic.
  Scope topics per-tenant instead — subscribe to an instance or tenant-derived
  topic, or broadcast to a narrower topic you derive from the writer's
  authority. `Hawk.PubSub` exposes the primitives; the host application owns the
  topic partitioning policy.
  """

  @doc """
  The resource topic for a Hawk resource facade.

      iex> Hawk.PubSub.topic(MyApp.Courses)
      "hawk:courses"

  The topic name is the facade module's last segment, underscored. Two facades
  backed by the same model but with different names (e.g. `MyApp.CourseCatalog`)
  get distinct topics.
  """
  @spec topic(module()) :: String.t()
  def topic(resource) when is_atom(resource) do
    "hawk:" <> resource_name(resource)
  end

  @doc """
  The instance topic for one record of a resource, keyed by identity value.

      iex> Hawk.PubSub.topic(MyApp.Courses, 42)
      "hawk:courses:42"

  The identity *field* (default `:id`, or whatever the facade declares with
  `identity:`) is read from the facade; the value passed here is the field's
  value on the changed record.
  """
  @spec topic(module(), term()) :: String.t()
  def topic(resource, identity_value) when is_atom(resource) do
    topic(resource) <> ":" <> to_string(identity_value)
  end

  @doc """
  Subscribes the calling process to a resource's change notifications.

  With `identity_value: nil` (default) subscribes to the resource topic — every
  create/update/delete for the resource. With a value, also subscribes to that
  record's instance topic, so a show screen receives only its own record's
  changes.

  Returns `:ok`. No-op safety is the caller's responsibility: pass a PubSub
  module that the host application starts and supervises.
  """
  @spec subscribe(module(), module(), term() | nil) :: :ok | {:error, term()}
  def subscribe(pubsub, resource, identity_value \\ nil)
      when is_atom(pubsub) and is_atom(resource) do
    :ok = Phoenix.PubSub.subscribe(pubsub, topic(resource))

    if identity_value != nil do
      :ok = Phoenix.PubSub.subscribe(pubsub, topic(resource, identity_value))
    end

    :ok
  end

  @doc """
  Reverses `subscribe/3`. Pass the same `identity_value` used to subscribe.
  """
  @spec unsubscribe(module(), module(), term() | nil) :: :ok
  def unsubscribe(pubsub, resource, identity_value \\ nil)
      when is_atom(pubsub) and is_atom(resource) do
    :ok = Phoenix.PubSub.unsubscribe(pubsub, topic(resource))

    if identity_value != nil do
      :ok = Phoenix.PubSub.unsubscribe(pubsub, topic(resource, identity_value))
    end

    :ok
  end

  @doc """
  Returns the PubSub configuration for a resource's writer, or `nil` when the
  writer did not declare `:pubsub`.

  The result is `%{pubsub: module, topic_strategy: module}`. The `topic_strategy`
  is the writer's configured strategy (`Hawk.PubSub.DefaultTopics` for the bare
  `pubsub: MyApp.PubSub` form, or the app's module for the tuple form
  `pubsub: {MyApp.PubSub, MyApp.PubSub.Topics}`).

  Used by `Hawk.LiveView.subscribe/2` so the application author passes only the
  resource; both the PubSub module and the topic strategy are read from it.
  """
  @spec config_for_resource(module()) :: %{pubsub: module(), topic_strategy: module()} | nil
  def config_for_resource(resource) when is_atom(resource) do
    writer = resource.__hawk_resource__(:writer)

    if function_exported?(writer, :__hawk_writer_opts__, 0) do
      opts = writer.__hawk_writer_opts__()

      case Keyword.get(opts, :pubsub) do
        nil ->
          nil

        pubsub ->
          %{pubsub: pubsub, topic_strategy: Keyword.get(opts, :topic_strategy) || Hawk.PubSub.DefaultTopics}
      end
    else
      nil
    end
  end

  @doc """
  Returns the `Phoenix.PubSub` module configured on a resource's writer, or
  `nil` when the writer did not declare `:pubsub`.

  Convenience over `config_for_resource/1` for callers that only need the
  PubSub module (e.g. to subscribe to a topic derived outside a strategy).
  """
  @spec for_resource(module()) :: module() | nil
  def for_resource(resource) when is_atom(resource) do
    case config_for_resource(resource) do
      nil -> nil
      %{pubsub: pubsub} -> pubsub
    end
  end

  @doc """
  Broadcasts a change event to the topics derived by `strategy`.

  The strategy's `broadcast_topics/3` decides the topics; this helper builds the
  `Hawk.PubSub.Event` from the model's declared identity and publishes it to
  each. Used by `Hawk.RepositoryBoundary` on a successful write.
  """
  @spec broadcast(module(), module(), module(), :create | :update | :delete, struct()) :: :ok
  def broadcast(pubsub, strategy, resource, operation, model)
      when is_atom(pubsub) and is_atom(strategy) and is_atom(resource) and is_struct(model) do
    identity = resource.__hawk_resource__(:identity)
    identity_value = Map.get(model, identity)

    event = %Hawk.PubSub.Event{
      resource: resource,
      operation: operation,
      identity: identity,
      identity_value: identity_value
    }

    for topic <- strategy.broadcast_topics(resource, operation, model) do
      :ok = Phoenix.PubSub.broadcast(pubsub, topic, event)
    end

    :ok
  end

  @doc """
  Broadcasts a change event using `Hawk.PubSub.DefaultTopics`.

  Convenience over `broadcast/5` for callers that want the default resource +
  instance topics without passing a strategy. The writer path uses `broadcast/5`
  with the configured strategy.
  """
  @spec broadcast(module(), module(), :create | :update | :delete, struct()) :: :ok
  def broadcast(pubsub, resource, operation, model)
      when is_atom(pubsub) and is_atom(resource) and is_struct(model) do
    broadcast(pubsub, Hawk.PubSub.DefaultTopics, resource, operation, model)
  end

  defp resource_name(resource) do
    resource |> Module.split() |> List.last() |> Macro.underscore()
  end
end
