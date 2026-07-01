defmodule Videdal.Students.WriterTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Videdal.Student
  alias Videdal.Students

  test "create runs through the resource writer pipeline" do
    authority = Authority.new(:school_admin, 1, scopes: %{school_id: 7})

    assert {:ok, %Student{name: "Ada", school_id: 7, active: true}} =
             Students.create(%{name: "Ada", school_id: 7}, authority)
  end

  test "create rejects readonly authorities" do
    authority =
      :school_admin
      |> Authority.new(1, scopes: %{school_id: 7})
      |> Authority.readonly()

    assert {:not_authorized, _context} =
             Students.create(%{name: "Ada", school_id: 7}, authority)
  end
end
