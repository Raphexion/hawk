defmodule Hawk.MultiTest do
  use Videdal.DatabaseCase, async: false

  alias Hawk.{Authority, Multi}

  @authority Authority.system()

  defmodule ForeignReader do
    @moduledoc false
    def repo, do: :foreign_repo
  end

  defp temporary_facade(reader) do
    name = Module.concat(__MODULE__, "Facade#{:erlang.unique_integer([:positive])}")

    contents =
      quote do
        @moduledoc false
        def __hawk_resource__(:reader), do: unquote(reader)
        def __hawk_resource__(_), do: nil
      end

    Module.create(name, contents, Macro.Env.location(__ENV__))
    name
  end

  describe "new/0" do
    test "returns an empty multi" do
      multi = Multi.new()
      assert multi.steps == []
    end
  end

  describe "create/4" do
    test "adds a named create step that calls the resource facade" do
      school = insert(:school)
      teacher = insert(:teacher, school_id: school.id)

      multi =
        Multi.new()
        |> Multi.create(
          :course,
          Videdal.Courses,
          %{title: "Math", school_id: school.id, teacher_id: teacher.id},
          @authority
        )

      assert length(multi.steps) == 1
      [step] = multi.steps
      assert step.name == :course
      assert step.op == :create
      assert step.resource == Videdal.Courses
      assert step.attrs == %{title: "Math", school_id: school.id, teacher_id: teacher.id}
      assert step.authority == @authority
    end
  end

  describe "update/4" do
    test "adds a named update step" do
      course = insert(:course)

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
      course = insert(:course)

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
      course = insert(:course)

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
      course = insert(:course)

      multi =
        Multi.new()
        |> Multi.delete(:course, Videdal.Courses, course, @authority)
        |> Multi.update(:other, Videdal.Courses, course, %{title: "X"}, @authority)

      steps = Multi.to_list(multi)
      assert length(steps) == 2
      assert Enum.map(steps, & &1.name) == [:course, :other]
    end
  end

  describe "to_changesets/1" do
    test "validates create and update steps without committing" do
      school = insert(:school)
      teacher = insert(:teacher, school_id: school.id)
      course = insert(:course, school_id: school.id, teacher_id: teacher.id)

      multi =
        Multi.new()
        |> Multi.create(
          :grade,
          Videdal.Grades,
          %{score: 7, school_id: school.id, student_id: teacher.id, course_id: course.id},
          @authority
        )
        |> Multi.update(:course, Videdal.Courses, course, %{title: "Science"}, @authority)

      changesets = Multi.to_changesets(multi)

      assert %Ecto.Changeset{} = changesets.grade
      assert changesets.grade.changes.score == 7
      assert changesets.grade.action == :validate
      assert %Ecto.Changeset{} = changesets.course
      assert changesets.course.changes.title == "Science"
    end

    test "does not touch the repo" do
      course = insert(:course)

      {changesets, count} =
        count_queries(fn ->
          Multi.to_changesets(
            Multi.new()
            |> Multi.update(:course, Videdal.Courses, course, %{title: "Science"}, @authority)
          )
        end)

      assert Map.has_key?(changesets, :course)
      assert count == 0
    end

    test "omits delete steps (no changeset to validate)" do
      course = insert(:course)

      multi =
        Multi.new()
        |> Multi.update(:course, Videdal.Courses, course, %{title: "Science"}, @authority)
        |> Multi.delete(:gone, Videdal.Courses, course, @authority)

      changesets = Multi.to_changesets(multi)
      assert Map.has_key?(changesets, :course)
      refute Map.has_key?(changesets, :gone)
    end

    test "raises for :run steps (run-only multis cannot be live-validated)" do
      multi =
        Multi.new()
        |> Multi.update(:course, Videdal.Courses, insert(:course), %{title: "X"}, @authority)
        |> Multi.run(:derived, fn _results -> {:ok, :x} end)

      assert_raise ArgumentError, ~r/run-only/, fn -> Multi.to_changesets(multi) end
    end

    test "raises for :action steps (run-only multis cannot be live-validated)" do
      course = insert(:course, registration_state: "draft", seat_count: 0, waitlist_count: 0)

      multi =
        Multi.new()
        |> Multi.action(:open, Videdal.Courses, course, "open-registration", %{seat_count: 2}, @authority)

      assert_raise ArgumentError, ~r/run-only/, fn -> Multi.to_changesets(multi) end
    end
  end

  describe "execute/3" do
    test "runs all steps in a single transaction and returns results" do
      course = insert(:course)

      multi =
        Multi.new()
        |> Multi.update(:course, Videdal.Courses, course, %{title: "Science"}, @authority)

      {:ok, results} = Multi.execute(multi, Videdal.Repo)

      assert Map.has_key?(results, :course)
      assert results.course.title == "Science"
    end

    test "threads prior step results to run/3 steps" do
      course = insert(:course)

      multi =
        Multi.new()
        |> Multi.update(:course, Videdal.Courses, course, %{title: "Science"}, @authority)
        |> Multi.run(:id, fn %{course: updated} -> {:ok, updated.id} end)

      {:ok, results} = Multi.execute(multi, Videdal.Repo)

      assert results.id == course.id
    end

    test "halts and rolls back when a step fails" do
      course = insert(:course)

      multi =
        Multi.new()
        |> Multi.update(:course, Videdal.Courses, course, %{title: "Science"}, @authority)
        |> Multi.create(:bad, Videdal.Courses, %{}, @authority)

      result = Multi.execute(multi, Videdal.Repo)

      assert {:error, :bad, _context, _prior} = result
      assert Videdal.Repo.reload(course).title == course.title
    end

    test "an empty multi succeeds with an empty results map" do
      {:ok, results} = Multi.execute(Multi.new(), Videdal.Repo)
      assert results == %{}
    end

    test "rejects a resource backed by a different repo" do
      multi =
        Multi.new()
        |> Multi.create(:foreign, temporary_facade(ForeignReader), %{}, @authority)

      assert_raise ArgumentError, ~r/requires every resource to use.*Videdal.Repo.*foreign_repo/s, fn ->
        Multi.execute(multi, Videdal.Repo)
      end
    end

    test "executes an action step and returns its result" do
      course = insert(:course, registration_state: "draft", seat_count: 0, waitlist_count: 0)

      multi =
        Multi.new()
        |> Multi.action(
          :open,
          Videdal.Courses,
          course,
          "open-registration",
          %{seat_count: 2, waitlist_count: 1},
          @authority
        )

      {:ok, results} = Multi.execute(multi, Videdal.Repo)

      assert results.open.registration_state == "open"
      assert results.open.seat_count == 2
    end

    test "run/3 receives prior step results and threads its value forward" do
      course = insert(:course)

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
      course = insert(:course)

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
