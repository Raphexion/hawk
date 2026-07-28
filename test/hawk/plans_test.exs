defmodule Hawk.PlansTest do
  use Videdal.DatabaseCase, async: true

  alias Hawk.{Authority, Plan, Plans}

  @authority Authority.system()

  describe "to_multi/2" do
    test "converts plan ops into a Hawk.Multi" do
      course = insert(:course)

      plan = Plan.new([
        %{op: :update, resource: "courses", id: course.id, attrs: %{title: "Science"}}
      ])

      {:ok, multi} = Plans.to_multi(plan, @authority)

      assert length(multi.steps) == 1
      [step] = multi.steps
      assert step.op == :update
      assert step.resource == Videdal.Courses
      assert step.attrs == %{title: "Science"}
    end

    test "resolves resource type strings to facades" do
      enrollment = insert(:enrollment)

      plan = Plan.new([
        %{op: :delete, resource: "enrollments", id: enrollment.id}
      ])

      {:ok, multi} = Plans.to_multi(plan, @authority)

      [step] = multi.steps
      assert step.op == :delete
      assert step.resource == Videdal.Enrollments
    end

    test "loads models for update/delete/action ops via the reader" do
      course = insert(:course)

      plan = Plan.new([
        %{op: :update, resource: "courses", id: course.id, attrs: %{title: "Science"}},
        %{op: :delete, resource: "courses", id: course.id}
      ])

      {:ok, multi} = Plans.to_multi(plan, @authority)

      assert length(multi.steps) == 2
      assert hd(multi.steps).model.id == course.id
      assert hd(multi.steps).attrs == %{title: "Science"}
    end

    test "handles action ops" do
      course = insert(:course)

      plan = Plan.new([
        %{op: :action, resource: "courses", id: course.id, action: "open-registration", params: %{seat_count: 2}}
      ])

      {:ok, multi} = Plans.to_multi(plan, @authority)

      [step] = multi.steps
      assert step.op == :action
      assert step.action == "open-registration"
      assert step.params == %{seat_count: 2}
    end

    test "returns error for unknown resource type" do
      plan = Plan.new([
        %{op: :delete, resource: "unknown-type", id: "x"}
      ])

      assert {:error, {:unknown_resource, "unknown-type"}} = Plans.to_multi(plan, @authority)
    end

    test "returns error when a member op references a missing record" do
      plan = Plan.new([
        %{op: :delete, resource: "courses", id: Ecto.UUID.generate()}
      ])

      assert {:error, {:not_found, "courses", _id}} = Plans.to_multi(plan, @authority)
    end
  end

  describe "run/3" do
    test "executes a plan transactionally and returns results" do
      course = insert(:course)

      plan = Plan.new([
        %{op: :update, resource: "courses", id: course.id, attrs: %{title: "Science"}}
      ])

      {:ok, results} = Plans.run(plan, @authority, Videdal.Repo)

      assert Map.has_key?(results, :step_1)
      assert results.step_1.title == "Science"
    end

    test "halts when a step fails" do
      course = insert(:course)

      plan = Plan.new([
        %{op: :update, resource: "courses", id: course.id, attrs: %{title: "Science"}},
        %{op: :create, resource: "courses", attrs: %{}}
      ])

      result = Plans.run(plan, @authority, Videdal.Repo)

      assert {:error, :step_2, _reason, _prior} = result
    end
  end

  describe "preview/2" do
    test "returns effects and rollback status without persisting" do
      course = insert(:course)

      plan = Plan.new([
        %{op: :update, resource: "courses", id: course.id, attrs: %{title: "Science"}}
      ])

      {:ok, effects} = Plans.preview(plan, @authority)

      assert Map.has_key?(effects, :step_1)

      # Verify rollback: the title should not have changed.
      reloaded = Videdal.Repo.get!(Videdal.Course, course.id)
      assert reloaded.title == course.title
    end

    test "returns error effects when the plan is invalid" do
      plan = Plan.new([
        %{op: :create, resource: "courses", attrs: %{}}
      ])

      result = Plans.preview(plan, @authority)

      assert {:error, :step_1, _reason, _prior} = result
    end
  end
end
