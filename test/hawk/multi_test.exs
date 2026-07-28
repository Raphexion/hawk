defmodule Hawk.MultiTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Hawk.Multi

  @school_id Videdal.school_id()
  @teacher_id Videdal.teacher_id()
  @course_id Videdal.course_id()
  @authority Authority.system()

  describe "new/0" do
    test "returns an empty multi" do
      multi = Multi.new()
      assert multi.steps == []
    end
  end

  describe "create/4" do
    test "adds a named create step that calls the resource facade" do
      course = %Videdal.Course{title: "Math", school_id: @school_id, teacher_id: @teacher_id}

      Process.put({Videdal.Repo, :all_results}, [course])

      multi =
        Multi.new()
        |> Multi.create(:course, Videdal.Courses, %{title: "Math", school_id: @school_id}, @authority)

      assert length(multi.steps) == 1
      [step] = multi.steps
      assert step.name == :course
      assert step.op == :create
      assert step.resource == Videdal.Courses
      assert step.attrs == %{title: "Math", school_id: @school_id}
      assert step.authority == @authority
    end
  end

  describe "update/4" do
    test "adds a named update step" do
      course = %Videdal.Course{id: @course_id, title: "Math"}

      multi =
        Multi.new()
        |> Multi.update(:course, Videdal.Courses, course, %{title: "Science"}, @authority)

      [step] = multi.steps
      assert step.name == :course
      assert step.op == :update
      assert step.model == course
      assert step.attrs == %{title: "Science"}
    end
  end

  describe "delete/3" do
    test "adds a named delete step" do
      course = %Videdal.Course{id: @course_id, title: "Math"}

      multi =
        Multi.new()
        |> Multi.delete(:course, Videdal.Courses, course, @authority)

      [step] = multi.steps
      assert step.name == :course
      assert step.op == :delete
      assert step.model == course
    end
  end

  describe "action/5" do
    test "adds a named action step" do
      course = %Videdal.Course{id: @course_id, title: "Math"}

      multi =
        Multi.new()
        |> Multi.action(:open, Videdal.Courses, course, "open-registration", %{seat_count: 2}, @authority)

      [step] = multi.steps
      assert step.name == :open
      assert step.op == :action
      assert step.action == "open-registration"
      assert step.params == %{seat_count: 2}
    end
  end

  describe "run/3" do
    test "adds a computed step whose result is threaded forward" do
      _course = %Videdal.Course{id: @course_id, title: "Math"}

      multi =
        Multi.new()
        |> Multi.create(:course, Videdal.Courses, %{title: "Math"}, @authority)
        |> Multi.run(:derived, fn %{course: created} -> {:ok, created.id} end)

      assert length(multi.steps) == 2
      [_create, run_step] = multi.steps
      assert run_step.name == :derived
      assert is_function(run_step.fun, 1)
    end
  end

  describe "to_list/1" do
    test "returns the steps without executing" do
      course = %Videdal.Course{id: @course_id, title: "Math"}

      multi =
        Multi.new()
        |> Multi.delete(:course, Videdal.Courses, course, @authority)
        |> Multi.update(:other, Videdal.Courses, course, %{title: "X"}, @authority)

      steps = Multi.to_list(multi)
      assert length(steps) == 2
      assert Enum.map(steps, & &1.name) == [:course, :other]
    end
  end

  describe "execute/3" do
    test "runs all steps in a single transaction and returns results" do
      course = %Videdal.Course{id: @course_id, title: "Math", school_id: @school_id, teacher_id: @teacher_id}

      Process.put({Videdal.Repo, :all_results}, [course])

      multi =
        Multi.new()
        |> Multi.update(:course, Videdal.Courses, course, %{title: "Science"}, @authority)

      {:ok, results} = Multi.execute(multi, Videdal.Repo)

      assert Map.has_key?(results, :course)
      assert results.course.title == "Science"
      assert_received {:videdal_repo, :transaction}
    end

    test "threads prior step results to run/3 steps" do
      course = %Videdal.Course{id: @course_id, title: "Math", school_id: @school_id, teacher_id: @teacher_id}

      Process.put({Videdal.Repo, :all_results}, [course])

      multi =
        Multi.new()
        |> Multi.update(:course, Videdal.Courses, course, %{title: "Science"}, @authority)
        |> Multi.run(:id, fn %{course: updated} -> {:ok, updated.id} end)

      {:ok, results} = Multi.execute(multi, Videdal.Repo)

      assert results.id == @course_id
    end

    test "halts and rolls back when a step fails" do
      course = %Videdal.Course{id: @course_id, title: "Math", school_id: @school_id, teacher_id: @teacher_id}

      Process.put({Videdal.Repo, :all_results}, [course])

      # A create that will fail validation: missing required fields.
      multi =
        Multi.new()
        |> Multi.update(:course, Videdal.Courses, course, %{title: "Science"}, @authority)
        |> Multi.create(:bad, Videdal.Courses, %{}, @authority)

      result = Multi.execute(multi, Videdal.Repo)

      assert {:error, :bad, _context, _prior} = result
    end

    test "an empty multi succeeds with an empty results map" do
      {:ok, results} = Multi.execute(Multi.new(), Videdal.Repo)
      assert results == %{}
    end

    test "executes an action step and returns its result" do
      course = %Videdal.Course{id: @course_id, title: "Math", school_id: @school_id, teacher_id: @teacher_id, registration_state: "draft", seat_count: 0, waitlist_count: 0}

      Process.put({Videdal.Repo, :all_results}, [course])

      multi =
        Multi.new()
        |> Multi.action(:open, Videdal.Courses, course, "open-registration", %{seat_count: 2, waitlist_count: 1}, @authority)

      {:ok, results} = Multi.execute(multi, Videdal.Repo)

      assert results.open.registration_state == "open"
      assert results.open.seat_count == 2
    end

    test "run/3 receives prior step results and threads its value forward" do
      course = %Videdal.Course{id: @course_id, title: "Math", school_id: @school_id, teacher_id: @teacher_id}

      Process.put({Videdal.Repo, :all_results}, [course])

      multi =
        Multi.new()
        |> Multi.update(:course, Videdal.Courses, course, %{title: "Science"}, @authority)
        |> Multi.run(:after, fn %{course: updated} -> {:ok, updated.title} end)
        |> Multi.run(:final, fn %{after: title} -> {:ok, String.upcase(title)} end)

      {:ok, results} = Multi.execute(multi, Videdal.Repo)

      assert results.after == "Science"
      assert results.final == "SCIENCE"
    end

    test "a failed run/3 halts the multi and rolls back prior steps" do
      course = %Videdal.Course{id: @course_id, title: "Math", school_id: @school_id, teacher_id: @teacher_id}

      Process.put({Videdal.Repo, :all_results}, [course])

      multi =
        Multi.new()
        |> Multi.update(:course, Videdal.Courses, course, %{title: "Science"}, @authority)
        |> Multi.run(:fail, fn _results -> {:error, :deliberate_failure} end)

      result = Multi.execute(multi, Videdal.Repo)

      assert {:error, :fail, :deliberate_failure, prior} = result
      assert Map.has_key?(prior, :course)
    end
  end
end
