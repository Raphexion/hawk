defmodule Hawk.AuthoritySessionTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Hawk.Authority.Session

  test "dumps and loads authorities for sessions" do
    authority = Authority.new(:teacher, 12, scopes: %{school_id: 7}, meta: %{name: "Lena"})

    assert %Authority{role: :teacher, identity: 12, scopes: %{school_id: 7}} =
             authority |> Session.dump() |> Session.load()
  end

  test "assigns and fetches authority using the default key" do
    authority = Authority.new(:parent, 4)
    socket = Session.assign_authority(%{assigns: %{}}, authority)

    assert Session.fetch_authority(socket) == {:ok, authority}
  end

  test "falls back to public authority" do
    assert %Authority{role: :public, public?: true, readonly?: true} =
             Session.authority_or_public(%{})
  end
end
