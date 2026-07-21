defmodule Hawk.PolicyTest.ExamplePolicy do
  @moduledoc false

  use Hawk.Policy

  read do
    role(:system, :all)
    role(:principal, :all)
    role(:school_admin, scopes: [:school_id])
    role(:teacher, scopes: [:school_id, :teacher_id])
    role(:student, scopes: [:school_id, :student_id], filter: %{active: true})
  end

  write(roles: [:principal, :teacher])
end

defmodule Hawk.PolicyTest.OwnedPolicy do
  use Hawk.Policy

  read(:all)
  write(roles: [:teacher], owned_by: [teacher_id: :teacher_id])
end

defmodule Hawk.PolicyTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Hawk.MutationContext
  alias Hawk.PolicyTest.{ExamplePolicy, OwnedPolicy}
  alias Videdal.{Course, Grade}

  test "read role declarations return all for unrestricted roles" do
    assert ExamplePolicy.read_filter(Authority.system()) == :all
    assert ExamplePolicy.read_filter(Authority.new(:principal, 1)) == :all
  end

  test "read role declarations build filters from authority scopes" do
    authority = Authority.new(:teacher, 12, scopes: %{school_id: 7, teacher_id: 12})

    assert ExamplePolicy.read_filter(authority) == %{school_id: 7, teacher_id: 12}
  end

  test "read role declarations merge static filters" do
    authority = Authority.new(:student, 8, scopes: %{school_id: 7, student_id: 8})

    assert ExamplePolicy.read_filter(authority) == %{school_id: 7, student_id: 8, active: true}
  end

  test "read role declarations fail closed when a required scope is missing" do
    authority = Authority.new(:teacher, 12, scopes: %{school_id: 7})

    assert ExamplePolicy.read_filter(authority) == :none
  end

  test "policy exposes introspection metadata" do
    assert ExamplePolicy.__hawk_policy__() == %{
             read: [
               {:system, :all},
               {:principal, :all},
               {:school_admin, {:scoped, [:school_id], %{}}},
               {:teacher, {:scoped, [:school_id, :teacher_id], %{}}},
               {:student, {:scoped, [:school_id, :student_id], %{active: true}}}
             ]
           }
  end

  test "read role declarations fail closed for unknown roles" do
    assert ExamplePolicy.read_filter(Authority.new(:parent, 4)) == :none
  end

  test "write ownership declarations require matching authority scopes" do
    teacher_id = Videdal.teacher_id()
    other_teacher_id = Videdal.other_teacher_id()
    owned = %Course{teacher_id: teacher_id}

    matching =
      MutationContext.update(
        owned,
        %{},
        Authority.new(:teacher, teacher_id, scopes: %{teacher_id: teacher_id})
      )

    changed =
      owned
      |> MutationContext.update(
        %{teacher_id: other_teacher_id},
        Authority.new(:teacher, teacher_id, scopes: %{teacher_id: other_teacher_id})
      )
      |> Hawk.Writer.cast([:teacher_id])

    missing_scope = MutationContext.update(owned, %{}, Authority.new(:teacher, teacher_id))

    other =
      MutationContext.update(
        owned,
        %{},
        Authority.new(:teacher, other_teacher_id, scopes: %{teacher_id: other_teacher_id})
      )

    assert OwnedPolicy.update?(matching)
    assert OwnedPolicy.update?(changed)
    refute OwnedPolicy.update?(missing_scope)
    refute OwnedPolicy.update?(other)
  end

  test "write declarations allow configured roles and deny readonly authorities" do
    teacher_context = context(Authority.new(:teacher, 12))

    readonly_context =
      :teacher
      |> Authority.new(12)
      |> Authority.readonly()
      |> context()

    student_context = context(Authority.new(:student, 8))

    assert ExamplePolicy.create?(teacher_context)
    assert ExamplePolicy.update?(teacher_context)
    assert ExamplePolicy.delete?(teacher_context)
    refute ExamplePolicy.create?(readonly_context)
    refute ExamplePolicy.create?(student_context)
  end

  defp context(authority) do
    MutationContext.create(%Grade{}, %{}, authority)
  end
end
