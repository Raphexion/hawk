defmodule Videdal.PolicySupportTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Videdal.PolicySupport

  test "scoped_filter maps authority scopes into filter keys" do
    authority = Authority.new(:teacher, 12, scopes: %{school_id: 7, teacher_id: 12})

    assert PolicySupport.scoped_filter(authority, [:school_id, id: :teacher_id]) == %{
             school_id: 7,
             id: 12
           }
  end

  test "scoped_filter fails closed when required scope is missing" do
    authority = Authority.new(:teacher, 12, scopes: %{school_id: 7})

    assert PolicySupport.scoped_filter(authority, [:school_id, id: :teacher_id]) == :none
  end

  test "write_allowed denies readonly authorities even when role is allowed" do
    authority =
      :school_admin
      |> Authority.new(1)
      |> Authority.readonly()

    refute PolicySupport.write_allowed?(authority, [:school_admin])
  end
end
