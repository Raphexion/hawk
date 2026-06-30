defmodule Hawk.AuthorityTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority

  describe "new/3" do
    test "builds an actor authority" do
      authority =
        Authority.new(:teacher, 42,
          readonly?: true,
          scopes: %{school_id: 7},
          meta: %{request_id: "req-1"}
        )

      assert authority.role == :teacher
      assert authority.identity == 42
      assert authority.readonly?
      refute authority.system?
      assert authority.scopes == %{school_id: 7}
      assert authority.meta == %{request_id: "req-1"}
    end

    test "rejects non-atom roles" do
      assert_raise ArgumentError, ~r/role must be an atom/, fn ->
        Authority.new("teacher", 42)
      end
    end

    test "rejects non-map scopes" do
      assert_raise ArgumentError, ~r/scopes must be a map/, fn ->
        Authority.new(:teacher, 42, scopes: [school_id: 7])
      end
    end
  end

  describe "system/1" do
    test "builds a system authority" do
      authority = Authority.system(identity: :migration)

      assert Authority.system?(authority)
      refute Authority.readonly?(authority)
      assert authority.role == :system
      assert authority.identity == :migration
      assert authority.scopes == %{}
    end
  end

  describe "readonly/1" do
    test "returns a readonly authority without changing the original" do
      authority = Authority.new(:school_admin, 8, scopes: %{school_id: 3})
      readonly = Authority.readonly(authority)

      refute Authority.readonly?(authority)
      assert Authority.readonly?(readonly)
      assert readonly.role == authority.role
      assert readonly.identity == authority.identity
      assert readonly.scopes == authority.scopes
    end
  end

  describe "scopes" do
    test "fetches scoped values" do
      authority = Authority.new(:teacher, 42, scopes: %{school_id: 7})

      assert Authority.fetch_scope(authority, :school_id) == {:ok, 7}
      assert Authority.fetch_scope(authority, :student_id) == :error
      assert Authority.scope(authority, :student_id, :missing) == :missing
    end

    test "adds scoped values" do
      authority =
        :teacher
        |> Authority.new(42)
        |> Authority.put_scope(:school_id, 7)

      assert Authority.fetch_scope(authority, :school_id) == {:ok, 7}
    end
  end

  describe "cache_key/1" do
    test "is deterministic for equivalent scopes" do
      left = Authority.new(:teacher, 42, scopes: %{school_id: 7, classroom_id: 2})
      right = Authority.new(:teacher, 42, scopes: %{classroom_id: 2, school_id: 7})

      assert Authority.cache_key(left) == Authority.cache_key(right)
    end

    test "includes identity, readonly flag, system marker, and scopes" do
      base = Authority.new(:teacher, 42, scopes: %{school_id: 7})

      assert Authority.cache_key(base) !=
               Authority.cache_key(Authority.new(:teacher, 43, scopes: %{school_id: 7}))

      assert Authority.cache_key(base) !=
               Authority.cache_key(Authority.readonly(base))

      assert Authority.cache_key(base) !=
               Authority.cache_key(Authority.new(:teacher, 42, scopes: %{school_id: 8}))

      assert Authority.cache_key(base) !=
               Authority.cache_key(Authority.system(identity: 42, scopes: %{school_id: 7}))
    end
  end
end
