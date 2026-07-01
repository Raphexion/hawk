defmodule Hawk.RepositoryBoundaryTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Hawk.MutationContext
  alias Hawk.RepositoryBoundary
  alias Hawk.Writer
  alias Videdal.Repo
  alias Videdal.School
  alias Videdal.Student

  describe "insert/3" do
    test "persists valid system contexts without explicit policy validation" do
      context =
        %Student{}
        |> MutationContext.new(%{name: "Ada", school_id: 7}, Authority.system(), :create)
        |> Writer.cast([:name, :school_id])

      assert {:ok, %Student{name: "Ada", school_id: 7}} =
               RepositoryBoundary.insert(context, Repo, audit: audit_to_self())

      assert_received {:videdal_repo, :transaction}
      assert_received {:videdal_repo, :insert, _changeset}
      assert_received {:audit, %{operation: :insert, model: %Student{name: "Ada"}}}
    end

    test "persists valid ordinary contexts only after policy validation" do
      authority = Authority.new(:school_admin, 1, scopes: %{school_id: 7})

      context =
        %Student{}
        |> MutationContext.new(%{name: "Ada", school_id: 7}, authority, :create)
        |> Writer.cast([:name, :school_id])
        |> MutationContext.mark_policy_validated()

      assert {:ok, %Student{name: "Ada", school_id: 7}} =
               RepositoryBoundary.insert(context, Repo)
    end

    test "raises when an ordinary valid context skipped policy validation" do
      authority = Authority.new(:school_admin, 1, scopes: %{school_id: 7})

      context =
        %Student{}
        |> MutationContext.new(%{name: "Ada", school_id: 7}, authority, :create)
        |> Writer.cast([:name, :school_id])

      assert_raise RuntimeError, ~r/write policy has not been validated/, fn ->
        RepositoryBoundary.insert(context, Repo)
      end

      refute_received {:videdal_repo, :insert, _changeset}
    end

    test "does not persist invalid contexts" do
      context =
        %Student{}
        |> MutationContext.new(%{name: "Ada"}, Authority.system(), :create)
        |> Writer.cast([:name, :school_id])
        |> Writer.validate_required([:name, :school_id])

      assert {:invalid, ^context} = RepositoryBoundary.insert(context, Repo)
      refute_received {:videdal_repo, :insert, _changeset}
    end

    test "maps repo changeset errors back into an invalid context" do
      context =
        %Student{}
        |> MutationContext.new(%{active: "not-a-boolean"}, Authority.system(), :create)
        |> Writer.cast([:active])
        |> MutationContext.put_error(:none)

      assert {:invalid, returned_context} = RepositoryBoundary.insert(context, Repo)
      assert returned_context.error == :invalid
      assert returned_context.changeset.errors[:active]
      refute_received {:audit, _event}
    end

    test "preserves resolved belongs-to relations when the foreign key was persisted" do
      school = %School{id: 7, name: "Videdal Skole"}

      context =
        %Student{}
        |> MutationContext.new(
          %{name: "Ada", school_id: school.id, school: school},
          Authority.system(),
          :create
        )
        |> Writer.cast([:name, :school_id])

      assert {:ok, %Student{school_id: 7, school: ^school}} =
               RepositoryBoundary.insert(context, Repo)
    end

    test "does not preserve relations when the foreign key was not persisted" do
      school = %School{id: 7, name: "Videdal Skole"}

      context =
        %Student{}
        |> MutationContext.new(
          %{name: "Ada", school_id: school.id, school: school},
          Authority.system(),
          :create
        )
        |> Writer.cast([:name])

      assert {:ok, %Student{} = student} = RepositoryBoundary.insert(context, Repo)
      refute Ecto.assoc_loaded?(student.school)
      assert student.school_id == nil
    end
  end

  describe "update/3" do
    test "persists changed fields and audits successful updates" do
      context =
        %Student{id: 1, name: "Ada"}
        |> MutationContext.new(%{name: "Grace"}, Authority.system(), :update)
        |> Writer.cast([:name])

      assert {:ok, %Student{id: 1, name: "Grace"}} =
               RepositoryBoundary.update(context, Repo, audit: audit_to_self())

      assert_received {:videdal_repo, :update, _changeset}
      assert_received {:audit, %{operation: :update, model: %Student{name: "Grace"}}}
    end

    test "preserves resolved belongs-to relations when the foreign key changed" do
      school = %School{id: 8, name: "New School"}

      context =
        %Student{id: 1, name: "Ada", school_id: 7}
        |> MutationContext.new(
          %{school_id: school.id, school: school},
          Authority.system(),
          :update
        )
        |> Writer.cast([:school_id])

      assert {:ok, %Student{school_id: 8, school: ^school}} =
               RepositoryBoundary.update(context, Repo)
    end

    test "returns unchanged model without repo update or audit when nothing changed" do
      model = %Student{id: 1, name: "Ada"}
      context = MutationContext.new(model, %{}, Authority.system(), :update)

      assert RepositoryBoundary.update(context, Repo, audit: audit_to_self()) == {:ok, model}
      refute_received {:videdal_repo, :update, _changeset}
      refute_received {:audit, _event}
    end
  end

  describe "delete/3" do
    test "deletes valid contexts and audits successful deletes" do
      model = %Student{id: 1, name: "Ada"}
      context = MutationContext.new(model, %{}, Authority.system(), :delete)

      assert RepositoryBoundary.delete(context, Repo, audit: audit_to_self()) == {:ok, model}
      assert_received {:videdal_repo, :delete, ^model}
      assert_received {:audit, %{operation: :delete, model: ^model}}
    end

    test "does not delete unauthorized contexts" do
      context =
        %Student{id: 1, name: "Ada"}
        |> MutationContext.new(%{}, Authority.system(), :delete)
        |> MutationContext.validate_policy(fn _context -> false end)

      assert {:not_authorized, ^context} = RepositoryBoundary.delete(context, Repo)
      refute_received {:videdal_repo, :delete, _model}
    end
  end

  defp audit_to_self do
    test_pid = self()
    fn event -> send(test_pid, {:audit, event}) end
  end
end
