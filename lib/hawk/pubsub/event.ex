defmodule Hawk.PubSub.Event do
  @moduledoc """
  The change notification broadcast on every successful Hawk write.

  `Hawk.PubSub.broadcast/4` publishes an event to the resource topic and the
  instance topic. A LiveView (or any subscriber) matches it in `handle_info/2`
  and re-queries through its **own** authority — the event never carries the
  model, so the read policy (`read_filter/1`) is never bypassed.

  ## Fields

    * `:resource` — the `Hawk.Resource` facade that changed.
    * `:operation` — `:create`, `:update`, or `:delete`.
    * `:identity` — the identity field declared on the facade (default `:id`).
    * `:identity_value` — that field's value on the changed record.

  See `Hawk.PubSub` for topic derivation, subscribing, and the authority/
  existence caveat.
  """

  defstruct [:resource, :operation, :identity, :identity_value]

  @type t :: %__MODULE__{
          resource: module(),
          operation: :create | :update | :delete,
          identity: atom(),
          identity_value: term()
        }
end
