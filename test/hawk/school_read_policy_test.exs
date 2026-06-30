defmodule Hawk.SchoolReadPolicyTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Hawk.Filter
  alias Videdal.SchoolPolicy

  test "system and principal authorities can read all records" do
    assert SchoolPolicy.read_filter(Authority.system()) == :all
    assert SchoolPolicy.read_filter(Authority.new(:principal, 1)) == :all
  end

  test "unknown roles read no records" do
    assert SchoolPolicy.read_filter(Authority.new(:unknown, 1)) == :none
  end

  test "school admins are scoped by school" do
    authority = Authority.new(:school_admin, 10, scopes: %{school_id: 3})

    assert SchoolPolicy.read_filter(authority) == %{school_id: 3}
  end

  test "school admins without a school scope fail closed" do
    assert SchoolPolicy.read_filter(Authority.new(:school_admin, 10)) == :none
  end

  test "teachers are scoped by school and teacher" do
    authority = Authority.new(:teacher, 42, scopes: %{school_id: 3, teacher_id: 42})

    assert SchoolPolicy.read_filter(authority) == %{school_id: 3, teacher_id: 42}
  end

  test "students are scoped by school, student, and active records" do
    authority = Authority.new(:student, 99, scopes: %{school_id: 3, student_id: 99})

    assert SchoolPolicy.read_filter(authority) == %{school_id: 3, student_id: 99, active: true}
  end

  test "readonly authorities can still read" do
    authority =
      :teacher
      |> Authority.new(42, scopes: %{school_id: 3, teacher_id: 42})
      |> Authority.readonly()

    assert SchoolPolicy.read_filter(authority) == %{school_id: 3, teacher_id: 42}
  end

  test "policy filters compose with caller filters" do
    authority = Authority.new(:teacher, 42, scopes: %{school_id: 3, teacher_id: 42})

    assert Filter.and(%{course_id: 5}, SchoolPolicy.read_filter(authority)) == %{
             course_id: {:eq, 5},
             school_id: {:eq, 3},
             teacher_id: {:eq, 42}
           }
  end
end
