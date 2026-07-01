defmodule Videdal.Courses.WriterTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Videdal.Course
  alias Videdal.Courses

  test "create runs through the resource writer pipeline" do
    authority = Authority.new(:school_admin, 1, scopes: %{school_id: 7})

    assert {:ok, %Course{title: "Math", school_id: 7, teacher_id: 12}} =
             Courses.create(%{title: "Math", school_id: 7, teacher_id: 12}, authority)
  end

  test "create rejects missing required fields" do
    authority = Authority.new(:school_admin, 1, scopes: %{school_id: 7})

    assert {:invalid, context} = Courses.create(%{title: "Math", school_id: 7}, authority)
    assert context.changeset.errors[:teacher_id]
  end
end
