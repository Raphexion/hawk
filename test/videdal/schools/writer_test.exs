defmodule Videdal.Schools.WriterTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Videdal.School
  alias Videdal.Schools

  test "create runs through the resource writer pipeline" do
    assert {:ok, %School{name: "Videdal Skole"}} =
             Schools.create(%{name: "Videdal Skole"}, Authority.new(:principal, 1))
  end

  test "create rejects unauthorized authorities" do
    authority = Authority.new(:teacher, 1, scopes: %{school_id: 7})

    assert {:not_authorized, _context} = Schools.create(%{name: "Videdal Skole"}, authority)
  end
end
