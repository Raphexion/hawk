defmodule Videdal.Teachers.WriterTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Videdal.Teacher
  alias Videdal.Teachers

  test "create runs through the resource writer pipeline" do
    authority = Authority.new(:school_admin, 1, scopes: %{school_id: 7})

    assert {:ok, %Teacher{name: "Grace", school_id: 7}} =
             Teachers.create(%{name: "Grace", school_id: 7}, authority)
  end

  test "create rejects readonly authorities" do
    authority =
      :school_admin
      |> Authority.new(1, scopes: %{school_id: 7})
      |> Authority.readonly()

    assert {:not_authorized, _context} =
             Teachers.create(%{name: "Grace", school_id: 7}, authority)
  end

  test "update changes permitted fields through the repository boundary" do
    teacher = %Teacher{id: 12, name: "Grace", school_id: 7}
    authority = Authority.new(:school_admin, 1, scopes: %{school_id: 7})

    assert {:ok, %Teacher{id: 12, name: "Grace Hopper", school_id: 7}} =
             Teachers.update(teacher, %{name: "Grace Hopper", ignored: true}, authority)

    assert_received {:videdal_repo, :transaction}
    assert_received {:videdal_repo, :update, changeset}
    assert changeset.changes == %{name: "Grace Hopper"}
  end

  test "delete rejects readonly authorities before persistence" do
    teacher = %Teacher{id: 12, school_id: 7}

    authority =
      :school_admin
      |> Authority.new(1, scopes: %{school_id: 7})
      |> Authority.readonly()

    assert {:not_authorized, _context} = Teachers.delete(teacher, authority)
    refute_received {:videdal_repo, :delete, _teacher}
  end
end
