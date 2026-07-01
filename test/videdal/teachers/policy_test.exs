defmodule Videdal.Teachers.PolicyTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Hawk.MutationContext
  alias Videdal.Teacher
  alias Videdal.Teachers.Policy

  test "school admins are scoped by school" do
    authority = Authority.new(:school_admin, 1, scopes: %{school_id: 7})

    assert Policy.read_filter(authority) == %{school_id: 7}
  end

  test "teachers are scoped to their teacher record" do
    authority = Authority.new(:teacher, 12, scopes: %{school_id: 7, teacher_id: 12})

    assert Policy.read_filter(authority) == %{school_id: 7, id: 12}
  end

  test "students cannot read teacher records through this resource" do
    assert Policy.read_filter(Authority.new(:student, 1, scopes: %{school_id: 7})) == :none
  end

  test "school admins can write teachers" do
    context = context(Authority.new(:school_admin, 1, scopes: %{school_id: 7}))

    assert Policy.create?(context)
  end

  defp context(authority) do
    MutationContext.new(%Teacher{}, %{}, authority, :create)
  end
end
