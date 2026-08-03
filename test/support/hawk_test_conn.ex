defmodule Hawk.TestConn do
  @moduledoc """
  Shared test helpers for Hawk JSON:API controller and LiveView tests.

  `conn/0` builds a real `Plug.Conn` with the JSON:API request headers already
  set. `conn/1` accepts a `Hawk.Authority` (or `:public`) and assigns it under
  `:hawk_authority` so every Hawk entry point can read it.

  `resp/1` decodes a JSON:API response body into atom-keyed Elixir terms so
  assertions stay readable (`resp(conn).data.type`).
  """

  alias Hawk.Authority

  def conn(authority \\ Hawk.Authority.public())

  def conn(:public), do: conn(Authority.public())

  def conn(%Authority{} = authority) do
    Plug.Test.conn("get", "/")
    |> Plug.Conn.assign(:hawk_authority, authority)
  end

  def conn(authority_opts) when is_map(authority_opts) do
    %{role: role, scopes: scopes} = authority_opts
    identity = Map.get(authority_opts, :identity, 1)
    conn(Authority.new(role, identity, scopes: scopes))
  end

  @doc """
  Decodes a JSON:API response body into atom-keyed Elixir terms.
  """
  def resp(%Plug.Conn{resp_body: body}), do: Jason.decode!(body, keys: :atoms)
end
