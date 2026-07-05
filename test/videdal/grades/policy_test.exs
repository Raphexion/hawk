defmodule Videdal.Grades.PolicyTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Videdal.Grades.Policy

  test "teachers are scoped by school and teacher through courses" do
    authority = Authority.new(:teacher, 12, scopes: %{school_id: 7, teacher_id: 12})

    assert Policy.read_filter(authority) == %{school_id: 7, teacher_id: 12}
  end

  test "students are scoped to their own grades" do
    authority = Authority.new(:student, 8, scopes: %{school_id: 7, student_id: 8})

    assert Policy.read_filter(authority) == %{school_id: 7, student_id: 8}
  end

  test "parents are scoped through their linked students" do
    authority = Authority.new(:parent, 4, scopes: %{school_id: 7, parent_id: 4})

    assert Policy.read_filter(authority) == %{school_id: 7, parent_id: 4}
  end

  test "unknown roles read no grades" do
    assert Policy.read_filter(Authority.new(:unknown, 1)) == :none
  end
end
