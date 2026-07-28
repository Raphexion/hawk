defmodule Hawk.RepositoryBoundaryTest do
  use Videdal.DatabaseCase, async: true

  alias Hawk.{Authority, MutationContext, RepositoryBoundary, Writer}
  alias Videdal.{Repo, Student}

  describe "insert/3" do
    test "persists valid system contexts only after policy validation" do
      school = insert(:school)

      context =
        %Student{}
        |> MutationContext.create(%{name: "Ada", school_id: school.id}, Authority.system())
        |> Writer.cast([:name, :school_id])
        |> MutationContext.mark_policy_validated()

      assert {:ok, %Student{name: "Ada"} = student} =
               RepositoryBoundary.insert(context, Repo, audit: audit_to_self())
      assert student.school_id == school.id

      assert_received {:audit, %{operation: :insert, model: %Student{name: "Ada"}}}
    end

    test "raises when a system context skipped policy validation" do
      school = insert(:school)

      context =
        %Student{}
        |> MutationContext.create(%{name: "Ada", school_id: school.id}, Authority.system())
        |> Writer.cast([:name, :school_id])

      assert_raise RuntimeError, ~r/write policy has not been validated/, fn ->
        RepositoryBoundary.insert(context, Repo)
      end
    end

    test "persists valid ordinary contexts only after policy validation" do
      school = insert(:school)
      authority = Authority.new(:school_admin, 1, scopes: %{school_id: school.id})

      context =
        %Student{}
        |> MutationContext.create(%{name: "Ada", school_id: school.id}, authority)
        |> Writer.cast([:name, :school_id])
        |> MutationContext.mark_policy_validated()

      assert {:ok, %Student{name: "Ada"} = student} =
               RepositoryBoundary.insert(context, Repo)
      assert student.school_id == school.id
    end

    test "raises when an ordinary valid context skipped policy validation" do
      school = insert(:school)
      authority = Authority.new(:school_admin, 1, scopes: %{school_id: school.id})

      context =
        %Student{}
        |> MutationContext.create(%{name: "Ada", school_id: school.id}, authority)
        |> Writer.cast([:name, :school_id])

      assert_raise RuntimeError, ~r/write policy has not been validated/, fn ->
        RepositoryBoundary.insert(context, Repo)
      end
    end

    test "does not persist invalid contexts" do
      context =
        %Student{}
        |> MutationContext.create(%{name: "Ada"}, Authority.system())
        |> Writer.cast([:name, :school_id])
        |> Writer.validate_required([:name, :school_id])

      assert {:invalid, ^context} = RepositoryBoundary.insert(context, Repo)
    end

    test "maps repo changeset errors back into an invalid context" do
      context =
        %Student{}
        |> MutationContext.create(%{active: "not-a-boolean"}, Authority.system())
        |> Writer.cast([:active])
        |> MutationContext.put_error(:none)
        |> MutationContext.mark_policy_validated()

      assert {:invalid, returned_context} = RepositoryBoundary.insert(context, Repo)
      assert returned_context.error == :invalid
      assert returned_context.changeset.errors[:active]
    end

    test "preserves resolved belongs-to relations when the foreign key was persisted" do
      school = insert(:school)

      context =
        %Student{}
        |> MutationContext.create(
          %{name: "Ada", school_id: school.id, school: school},
          Authority.system()
        )
        |> Writer.cast([:name, :school_id])
        |> MutationContext.mark_policy_validated()

      assert {:ok, %Student{} = student} = RepositoryBoundary.insert(context, Repo)
      assert student.school_id == school.id
      assert student.school == school
    end

    test "does not preserve relations when the foreign key was not persisted" do
      school = insert(:school)

      context =
        %Student{}
        |> MutationContext.create(
          %{name: "Ada", school_id: school.id, school: school},
          Authority.system()
        )
        |> Writer.cast([:name])
        |> MutationContext.mark_policy_validated()

      assert {:ok, %Student{} = student} = RepositoryBoundary.insert(context, Repo)
      refute Ecto.assoc_loaded?(student.school)
      assert student.school_id == nil
    end
  end

  describe "update/3" do
    test "persists changed fields and audits successful updates" do
      student = insert(:student, name: "Ada")

      context =
        student
        |> MutationContext.update(%{name: "Grace"}, Authority.system())
        |> Writer.cast([:name])
        |> MutationContext.mark_policy_validated()

      assert {:ok, %Student{name: "Grace"} = updated} =
               RepositoryBoundary.update(context, Repo, audit: audit_to_self())
      assert updated.id == student.id

      assert_received {:audit, %{operation: :update, model: %Student{name: "Grace"}}}
    end

    test "preserves resolved belongs-to relations when the foreign key changed" do
      student = insert(:student)
      new_school = insert(:school)

      context =
        student
        |> MutationContext.update(
          %{school_id: new_school.id, school: new_school},
          Authority.system()
        )
        |> Writer.cast([:school_id])
        |> MutationContext.mark_policy_validated()

      assert {:ok, %Student{} = updated} = RepositoryBoundary.update(context, Repo)
      assert updated.school_id == new_school.id
      assert updated.school == new_school
    end

    test "returns unchanged model without repo update or audit when nothing changed" do
      student = insert(:student, name: "Ada")

      context =
        MutationContext.update(student, %{}, Authority.system())
        |> MutationContext.mark_policy_validated()

      assert RepositoryBoundary.update(context, Repo, audit: audit_to_self()) == {:ok, student}
      refute_received {:audit, _event}
    end
  end

  describe "delete/3" do
    test "deletes valid contexts and audits successful deletes" do
      student = insert(:student, name: "Ada")

      context =
        MutationContext.delete(student, Authority.system())
        |> MutationContext.mark_policy_validated()

      assert {:ok, deleted} = RepositoryBoundary.delete(context, Repo, audit: audit_to_self())
      assert deleted.id == student.id
      student_id = student.id
      assert_received {:audit, %{operation: :delete, model: %{id: ^student_id}}}
    end

    test "does not delete unauthorized contexts" do
      student = insert(:student, name: "Ada")

      context =
        student
        |> MutationContext.delete(Authority.system())
        |> MutationContext.validate_policy(fn _context -> false end)

      assert {:not_authorized, ^context} = RepositoryBoundary.delete(context, Repo)
    end
  end

  defp audit_to_self do
    test_pid = self()
    fn event -> send(test_pid, {:audit, event}) end
  end
end
