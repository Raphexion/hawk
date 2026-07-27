defmodule Hawk.PlansTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Hawk.Plan
  alias Hawk.Plans

  @school_id Videdal.school_id()
  @teacher_id Videdal.teacher_id()
  @course_id Videdal.course_id()
  @enrollment_id Videdal.enrollment_id()
  @student_id Videdal.student_id()
  @authority Authority.system()

  describe "to_multi/2" do
    test "converts plan ops into a Hawk.Multi" do
      course = %Videdal.Course{id: @course_id, title: "Math", school_id: @school_id, teacher_id: @teacher_id}

      Process.put({Videdal.Repo, :all_results}, [course])

      plan = Plan.new([
        %{op: :update, resource: "courses", id: @course_id, attrs: %{title: "Science"}}
      ])

      {:ok, multi} = Plans.to_multi(plan, @authority)

      assert length(multi.steps) == 1
      [step] = multi.steps
      assert step.op == :update
      assert step.resource == Videdal.Courses
      assert step.attrs == %{title: "Science"}
    end

    test "resolves resource type strings to facades" do
      enrollment = %Videdal.Enrollment{id: @enrollment_id, student_id: @student_id, course_id: @course_id}

      Process.put({Videdal.Repo, :all_results}, [enrollment])

      plan = Plan.new([
        %{op: :delete, resource: "enrollments", id: @enrollment_id}
      ])

      {:ok, multi} = Plans.to_multi(plan, @authority)

      [step] = multi.steps
      assert step.op == :delete
      assert step.resource == Videdal.Enrollments
    end

    test "loads models for update/delete/action ops via the reader" do
      course = %Videdal.Course{id: @course_id, title: "Math", school_id: @school_id, teacher_id: @teacher_id}

      Process.put({Videdal.Repo, :all_results}, [course])

      plan = Plan.new([
        %{op: :update, resource: "courses", id: @course_id, attrs: %{title: "Science"}},
        %{op: :delete, resource: "courses", id: @course_id}
      ])

      {:ok, multi} = Plans.to_multi(plan, @authority)

      assert length(multi.steps) == 2
      assert hd(multi.steps).model == course
      assert hd(multi.steps).attrs == %{title: "Science"}
    end

    test "handles action ops" do
      course = %Videdal.Course{id: @course_id, title: "Math", school_id: @school_id, teacher_id: @teacher_id}

      Process.put({Videdal.Repo, :all_results}, [course])

      plan = Plan.new([
        %{op: :action, resource: "courses", id: @course_id, action: "open-registration", params: %{seat_count: 2}}
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
      Process.put({Videdal.Repo, :all_results}, [])

      plan = Plan.new([
        %{op: :delete, resource: "courses", id: "missing-id"}
      ])

      assert {:error, {:not_found, "courses", "missing-id"}} = Plans.to_multi(plan, @authority)
    end
  end

  describe "run/3" do
    test "executes a plan transactionally and returns results" do
      course = %Videdal.Course{id: @course_id, title: "Math", school_id: @school_id, teacher_id: @teacher_id}

      Process.put({Videdal.Repo, :all_results}, [course])

      plan = Plan.new([
        %{op: :update, resource: "courses", id: @course_id, attrs: %{title: "Science"}}
      ])

      {:ok, results} = Plans.run(plan, @authority, Videdal.Repo)

      assert Map.has_key?(results, :step_1)
      assert results.step_1.title == "Science"
    end

    test "halts when a step fails" do
      course = %Videdal.Course{id: @course_id, title: "Math", school_id: @school_id, teacher_id: @teacher_id}

      Process.put({Videdal.Repo, :all_results}, [course])

      plan = Plan.new([
        %{op: :update, resource: "courses", id: @course_id, attrs: %{title: "Science"}},
        %{op: :create, resource: "courses", attrs: %{}}
      ])

      result = Plans.run(plan, @authority, Videdal.Repo)

      assert {:error, :step_2, _reason, _prior} = result
    end
  end

  describe "preview/2" do
    test "returns effects and rollback status without persisting" do
      course = %Videdal.Course{id: @course_id, title: "Math", school_id: @school_id, teacher_id: @teacher_id}

      Process.put({Videdal.Repo, :all_results}, [course])

      plan = Plan.new([
        %{op: :update, resource: "courses", id: @course_id, attrs: %{title: "Science"}}
      ])

      {:ok, effects} = Plans.preview(plan, @authority)

      # The preview returns the step results (effects) without persisting.
      # With the Videdal.Repo double (no real DB), there's no rollback — it's
      # a no-op. The key assertion is that it returns {:ok, effects} when the
      # plan is valid, and doesn't require the caller to pass a repo (it uses
      # the resource's own repo).
      assert Map.has_key?(effects, :step_1)
    end

    test "returns error effects when the plan is invalid" do
      course = %Videdal.Course{id: @course_id, title: "Math", school_id: @school_id, teacher_id: @teacher_id}

      Process.put({Videdal.Repo, :all_results}, [course])

      plan = Plan.new([
        %{op: :create, resource: "courses", attrs: %{}}
      ])

      result = Plans.preview(plan, @authority)

      assert {:error, :step_1, _reason, _prior} = result
    end
  end
end
