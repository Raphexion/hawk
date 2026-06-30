defmodule Hawk.MutationContextTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Hawk.MutationContext
  alias Hawk.TestSupport.School.Student

  describe "new/4" do
    test "initializes write state" do
      model = %Student{}
      attrs = %{name: "Ada"}
      authority = Authority.new(:school_admin, 1, scopes: %{school_id: 3})

      context = MutationContext.new(model, attrs, authority, :create)

      assert context.model == model
      assert context.attrs == attrs
      assert context.authority == authority
      assert context.changeset.data == model
      assert context.error == :none
      refute context.policy_validated?
      assert context.operation == :create
      assert context.meta == %{}
    end

    test "rejects unknown operations" do
      assert_raise ArgumentError, ~r/operation must be one of/, fn ->
        MutationContext.new(%Student{}, %{}, Authority.system(), :archive)
      end
    end
  end

  describe "add_error/4" do
    test "marks the context invalid and adds a changeset error" do
      context =
        %Student{}
        |> MutationContext.new(%{}, Authority.system(), :create)
        |> MutationContext.add_error(:name, "can't be blank")

      assert context.error == :invalid
      assert context.changeset.errors[:name] == {"can't be blank", []}
    end
  end

  describe "guard/2" do
    test "runs when the context has no error" do
      context = MutationContext.new(%Student{}, %{}, Authority.system(), :update)

      context =
        MutationContext.guard(context, fn context ->
          MutationContext.put_meta(context, :ran?, true)
        end)

      assert context.meta.ran?
    end

    test "does not run after an error" do
      context =
        %Student{}
        |> MutationContext.new(%{}, Authority.system(), :update)
        |> MutationContext.add_error(:name, "can't be blank")

      guarded =
        MutationContext.guard(context, fn _context ->
          flunk("guarded function should not run")
        end)

      assert guarded == context
    end
  end

  describe "validate_policy/2" do
    test "marks the context policy-validated when allowed" do
      context = MutationContext.new(%Student{}, %{}, Authority.system(), :delete)

      context = MutationContext.validate_policy(context, fn _context -> true end)

      assert context.error == :none
      assert context.policy_validated?
    end

    test "marks the context not authorized when denied" do
      context = MutationContext.new(%Student{}, %{}, Authority.system(), :delete)

      context = MutationContext.validate_policy(context, fn _context -> false end)

      assert context.error == :not_authorized
      assert context.policy_validated?
    end

    test "does not run after an error" do
      context =
        %Student{}
        |> MutationContext.new(%{}, Authority.system(), :delete)
        |> MutationContext.add_error(:name, "can't be blank")

      guarded =
        MutationContext.validate_policy(context, fn _context ->
          flunk("policy should not run after an invalid context")
        end)

      assert guarded == context
    end
  end
end
