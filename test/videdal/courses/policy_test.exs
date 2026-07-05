defmodule Videdal.Courses.PolicyTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Hawk.MutationContext
  alias Videdal.Course
  alias Videdal.Courses.Policy

  test "teachers are scoped by school and teacher" do
    authority = Authority.new(:teacher, 12, scopes: %{school_id: 7, teacher_id: 12})

    assert Policy.read_filter(authority) == %{school_id: 7, teacher_id: 12}
  end

  test "students are scoped by school for course reads" do
    authority = Authority.new(:student, 8, scopes: %{school_id: 7, student_id: 8})

    assert Policy.read_filter(authority) == %{school_id: 7}
  end

  test "unknown roles read no courses" do
    assert Policy.read_filter(Authority.new(:unknown, 1)) == :none
  end

  test "school admins can write courses" do
    context = context(Authority.new(:school_admin, 1, scopes: %{school_id: 7}))

    assert Policy.create?(context)
  end

  defp context(authority) do
    MutationContext.create(%Course{}, %{}, authority)
  end
end
