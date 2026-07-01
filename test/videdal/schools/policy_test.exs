defmodule Videdal.Schools.PolicyTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Hawk.MutationContext
  alias Videdal.School
  alias Videdal.Schools.Policy

  test "principals can read all schools" do
    assert Policy.read_filter(Authority.new(:principal, 1)) == :all
  end

  test "school-scoped roles read only their school" do
    assert Policy.read_filter(Authority.new(:teacher, 1, scopes: %{school_id: 7})) == %{id: 7}
  end

  test "unknown roles read no schools" do
    assert Policy.read_filter(Authority.new(:unknown, 1)) == :none
  end

  test "only principals and system authorities can write schools" do
    principal_context = context(Authority.new(:principal, 1))
    teacher_context = context(Authority.new(:teacher, 1, scopes: %{school_id: 7}))

    assert Policy.create?(principal_context)
    refute Policy.create?(teacher_context)
  end

  defp context(authority) do
    MutationContext.new(%School{}, %{}, authority, :create)
  end
end
