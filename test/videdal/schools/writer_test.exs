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

  test "update changes permitted fields through the repository boundary" do
    school = %School{id: 7, name: "Old"}

    assert {:ok, %School{id: 7, name: "New"}} =
             Schools.update(school, %{name: "New", ignored: true}, Authority.new(:principal, 1))

    assert_received {:videdal_repo, :transaction}
    assert_received {:videdal_repo, :update, changeset}
    assert changeset.changes == %{name: "New"}
  end

  test "delete runs through the repository boundary" do
    school = %School{id: 7, name: "Videdal Skole"}

    assert {:ok, ^school} = Schools.delete(school, Authority.new(:principal, 1))

    assert_received {:videdal_repo, :transaction}
    assert_received {:videdal_repo, :delete, ^school}
  end
end
