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

  test "update changes enrollment fields through the repository boundary" do
    enrollment = %Enrollment{id: 1, school_id: 7, student_id: 8, course_id: 3}
    authority = Authority.new(:school_admin, 1, scopes: %{school_id: 7})

    assert {:ok, %Enrollment{id: 1, course_id: 4, enrolled_on: ~D[2026-01-01]}} =
             Enrollments.update(
               enrollment,
               %{course_id: 4, enrolled_on: ~D[2026-01-01]},
               authority
             )

    assert_received {:videdal_repo, :transaction}
    assert_received {:videdal_repo, :update, changeset}
    assert changeset.changes == %{course_id: 4, enrolled_on: ~D[2026-01-01]}
  end

  test "delete rejects unauthorized authorities before persistence" do
    enrollment = %Enrollment{id: 1, school_id: 7, student_id: 8, course_id: 3}
    authority = Authority.new(:student, 8, scopes: %{school_id: 7, student_id: 8})

    assert {:not_authorized, _context} = Enrollments.delete(enrollment, authority)
    refute_received {:videdal_repo, :delete, _enrollment}
  end
end
