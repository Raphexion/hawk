defmodule Hawk.LiveView.AuthorityHook do
  @moduledoc """
  Optional LiveView `on_mount` convention for assigning Hawk authorities.

  Use after storing a dumped authority in the session with
  `Hawk.Authority.Session.dump/1`:

      on_mount {Hawk.LiveView.AuthorityHook, []}

  The hook assigns `:hawk_authority`, falling back to `Hawk.Authority.public()`.
  """

  alias Hawk.Authority.Session

  def on_mount(opts, _params, session, socket) do
    key = Keyword.get(opts, :assign, Session.default_key())
    session_key = Keyword.get(opts, :session_key, key)
    authority = Session.authority_or_public(session, session_key)

    {:cont, Session.assign_authority(socket, authority, key)}
  end
end
