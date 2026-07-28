defmodule Hawk.Authority.Plug do
  @moduledoc """
  Optional Plug-style authority assignment convention.

  Configure with a resolver that turns a conn into `Hawk.Authority`:

      plug Hawk.Authority.Plug, resolver: &MyAppWeb.Auth.authority/1

  If the resolver returns `nil`, Hawk assigns `Hawk.Authority.public()`.
  The authority is stored in `conn.assigns[:hawk_authority]` by default.
  """

  alias Hawk.Authority
  alias Hawk.Authority.Session

  @doc false
  def init(opts), do: opts

  @doc """
  Plug callback: resolves the authority from the configured `:resolver` and
  stores it under `:hawk_authority` (or the `:assign` key), defaulting to
  `Hawk.Authority.public/1` when the resolver returns `nil`.
  """
  def call(conn, opts) do
    key = Keyword.get(opts, :assign, Session.default_key())
    resolver = Keyword.get(opts, :resolver, fn _conn -> nil end)

    authority =
      case resolver.(conn) do
        %Authority{} = authority -> authority
        nil -> Authority.public()
      end

    Session.assign_authority(conn, authority, key)
  end
end
