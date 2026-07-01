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
end
