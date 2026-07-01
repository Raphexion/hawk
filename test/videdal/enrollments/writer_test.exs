defmodule Videdal.Enrollments.WriterTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Videdal.Enrollment
  alias Videdal.Enrollments

  test "create runs through the resource writer pipeline" do
    authority = Authority.new(:school_admin, 1, scopes: %{school_id: 7})

    assert {:ok, %Enrollment{school_id: 7, student_id: 8, course_id: 3}} =
             Enrollments.create(%{school_id: 7, student_id: 8, course_id: 3}, authority)
  end

  test "create accepts optional enrolled date" do
    authority = Authority.new(:school_admin, 1, scopes: %{school_id: 7})

    assert {:ok, %Enrollment{enrolled_on: ~D[2026-01-01]}} =
             Enrollments.create(
               %{school_id: 7, student_id: 8, course_id: 3, enrolled_on: ~D[2026-01-01]},
               authority
             )
  end
end
