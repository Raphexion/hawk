defmodule Videdal.Grades.PolicyTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Videdal.Grades.Policy

  test "principals can read all grades" do
    assert Policy.read_filter(Authority.new(:principal, 1)) == :all
  end

  test "school admins are scoped by school" do
    authority = Authority.new(:school_admin, 1, scopes: %{school_id: 7})

    assert Policy.read_filter(authority) == %{school_id: 7}
  end

  test "teachers are scoped by school and teacher through courses" do
    authority = Authority.new(:teacher, 12, scopes: %{school_id: 7, teacher_id: 12})

    assert Policy.read_filter(authority) == %{school_id: 7, teacher_id: 12}
  end

  test "students are scoped to their own grades" do
    authority = Authority.new(:student, 8, scopes: %{school_id: 7, student_id: 8})

    assert Policy.read_filter(authority) == %{school_id: 7, student_id: 8}
  end

  test "students without a student scope fail closed" do
    authority = Authority.new(:student, 8, scopes: %{school_id: 7})

    assert Policy.read_filter(authority) == :none
  end

  test "parents without a parent scope fail closed" do
    authority = Authority.new(:parent, 4, scopes: %{school_id: 7})

    assert Policy.read_filter(authority) == :none
  end

  test "parents are scoped through their linked students" do
    authority = Authority.new(:parent, 4, scopes: %{school_id: 7, parent_id: 4})

    assert Policy.read_filter(authority) == %{school_id: 7, parent_id: 4}
  end

  test "unknown roles read no grades" do
    assert Policy.read_filter(Authority.new(:unknown, 1)) == :none
  end

  test "policy does not own preload query construction" do
    refute function_exported?(Policy, :preload_query, 2)
  end
end
