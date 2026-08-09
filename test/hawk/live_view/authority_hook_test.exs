defmodule Hawk.LiveView.AuthorityHookTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Hawk.Authority.Session
  alias Hawk.LiveView.AuthorityHook

  test "assigns an authority from the default session key" do
    authority = Authority.new(:teacher, 12, scopes: %{school_id: 7})
    session = %{Session.default_key() => Session.dump(authority)}
    socket = %{assigns: %{}}

    assert {:cont, socket} = AuthorityHook.on_mount([], %{}, session, socket)

    assert %Authority{role: :teacher, identity: 12, scopes: %{school_id: 7}} =
             socket.assigns.hawk_authority
  end

  test "supports custom assign and session keys" do
    authority = Authority.new(:parent, 4)
    session = %{"current_authority" => Session.dump(authority)}
    socket = %{assigns: %{}}

    assert {:cont, socket} =
             AuthorityHook.on_mount(
               [assign: :current_authority, session_key: "current_authority"],
               %{},
               session,
               socket
             )

    assert %Authority{role: :parent, identity: 4} = socket.assigns.current_authority
    refute Map.has_key?(socket.assigns, :hawk_authority)
  end

  test "falls back to public authority when the session has no authority" do
    socket = %{assigns: %{}}

    assert {:cont, socket} = AuthorityHook.on_mount([], %{}, %{}, socket)

    assert %Authority{role: :public, public?: true, readonly?: true} =
             socket.assigns.hawk_authority
  end
end
