defmodule Videdal.Parents.ReaderTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Videdal.Parents.Policy

  test "policy exposes parents by role without leaking across schools" do
    assert Policy.read_filter(Authority.system()) == :all
    assert Policy.read_filter(Authority.new(:principal, 1)) == :all

    assert Policy.read_filter(Authority.new(:school_admin, 1, scopes: %{school_id: 7})) == %{
             school_id: 7
           }

    assert Policy.read_filter(Authority.new(:parent, 4, scopes: %{school_id: 7, parent_id: 4})) ==
             %{
               school_id: 7,
               parent_id: 4
             }

    assert Policy.read_filter(Authority.new(:parent, 4, scopes: %{school_id: 7})) == :none
  end
end
