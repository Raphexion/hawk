defmodule Videdal.Teachers.WriterTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Videdal.Teacher
  alias Videdal.Teachers

  @school_admin_id Videdal.school_admin_id()
  @school_id Videdal.school_id()
  @teacher_id Videdal.teacher_id()

  test "create runs through the resource writer pipeline" do
    authority = Authority.new(:school_admin, @school_admin_id, scopes: %{school_id: @school_id})

    assert {:ok, %Teacher{name: "Grace", school_id: @school_id}} =
             Teachers.create(%{name: "Grace", school_id: @school_id}, authority)
  end

  test "create rejects readonly authorities" do
    authority =
      :school_admin
      |> Authority.new(@school_admin_id, scopes: %{school_id: @school_id})
      |> Authority.readonly()

    assert {:not_authorized, _context} =
             Teachers.create(%{name: "Grace", school_id: @school_id}, authority)
  end

  test "update changes permitted fields through the repository boundary" do
    teacher = %Teacher{id: @teacher_id, name: "Grace", school_id: @school_id}
    authority = Authority.new(:school_admin, @school_admin_id, scopes: %{school_id: @school_id})

    assert {:ok, %Teacher{id: @teacher_id, name: "Grace Hopper", school_id: @school_id}} =
             Teachers.update(teacher, %{name: "Grace Hopper", ignored: true}, authority)

    assert_received {:videdal_repo, :transaction}
    assert_received {:videdal_repo, :update, changeset}
    assert changeset.changes == %{name: "Grace Hopper"}
  end

  test "delete rejects readonly authorities before persistence" do
    teacher = %Teacher{id: @teacher_id, school_id: @school_id}

    authority =
      :school_admin
      |> Authority.new(@school_admin_id, scopes: %{school_id: @school_id})
      |> Authority.readonly()

    assert {:not_authorized, _context} = Teachers.delete(teacher, authority)
    refute_received {:videdal_repo, :delete, _teacher}
  end
end
