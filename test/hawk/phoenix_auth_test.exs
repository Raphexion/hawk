defmodule Hawk.PhoenixAuthTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Hawk.PhoenixAuth

  defmodule User do
    defstruct [:id, :role, :school_id, :teacher_id]
  end

  defmodule Scope do
    defstruct [:user]

    def for_user(user), do: %__MODULE__{user: user}
  end

  defmodule Accounts do
    def get_user_by_session_token("valid-token") do
      {%User{id: 12, role: "teacher", school_id: 7, teacher_id: 12}, :token_record}
    end

    def get_user_by_session_token(_token), do: nil
  end

  test "builds Hawk authority from a generated auth scope" do
    scope = Scope.for_user(%User{id: 12, role: "teacher", school_id: 7, teacher_id: 12})

    assert %Authority{role: :teacher, identity: 12, scopes: %{school_id: 7, teacher_id: 12}} =
             PhoenixAuth.authority_from_scope(scope,
               role_path: [:role],
               scopes: [school_id: [:school_id], teacher_id: [:teacher_id]]
             )
  end

  test "missing scope becomes readonly public authority" do
    assert %Authority{role: :public, public?: true, readonly?: true} =
             PhoenixAuth.authority_from_scope(nil, role_path: [:role])
  end

  test "plug assigns current scope and authority from a Bearer token" do
    token = Base.url_encode64("valid-token", padding: false)
    conn = %{assigns: %{}, req_headers: [{"authorization", "Bearer #{token}"}]}

    conn =
      PhoenixAuth.call(conn,
        authority:
          {PhoenixAuth, :authority_from_scope,
           [[role_path: [:role], scopes: [school_id: [:school_id], teacher_id: [:teacher_id]]]]},
        bearer: [accounts: Accounts, scope: Scope]
      )

    assert %Scope{} = conn.assigns.current_scope
    assert %Authority{role: :teacher, scopes: %{school_id: 7, teacher_id: 12}} = conn.assigns.authority
    assert conn.assigns.hawk_authority == conn.assigns.authority
  end

  test "on_mount assigns authority from current_scope" do
    socket = %{
      assigns: %{
        current_scope: Scope.for_user(%User{id: 12, role: "teacher", school_id: 7, teacher_id: 12})
      }
    }

    assert {:cont, socket} =
             PhoenixAuth.on_mount(
               {:mount_current_authority,
                [
                  authority:
                    {PhoenixAuth, :authority_from_scope,
                     [[role_path: [:role], scopes: [school_id: [:school_id], teacher_id: [:teacher_id]]]]}
                ]},
               %{},
               %{},
               socket
             )

    assert %Authority{role: :teacher, scopes: %{teacher_id: 12}} = socket.assigns.hawk_authority
  end

  test "normalize_role resolves a role string whose atom is not yet loaded" do
    # Use a deliberately-unique role string that no other code path loads as an
    # atom, so `String.to_existing_atom/1` would fail in isolation. The auth
    # path must not crash on role strings from the database that arrive before
    # their policy atom is loaded (the order-dependent crash that motivated
    # this fix).
    unique_role = "phoenix_auth_test_unique_role_#{System.unique_integer([:positive])}"

    scope = Scope.for_user(%User{id: 99, role: unique_role})

    assert %Authority{role: role_atom, identity: 99} =
             PhoenixAuth.authority_from_scope(scope, role_path: [:role])

    assert is_atom(role_atom)
    assert Atom.to_string(role_atom) == unique_role
  end
end
