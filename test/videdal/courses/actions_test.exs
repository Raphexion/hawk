defmodule Videdal.Courses.ActionsTest do
  use Videdal.DatabaseCase, async: true

  alias Hawk.Authority
  alias Videdal.{Course, Grade, Repo}
  alias Videdal.Courses.Actions

  @authority Authority.system()

  describe "submit-grade (two-phase)" do
    test "change/3 validates both steps without committing" do
      school = insert(:school)
      teacher = insert(:teacher, school_id: school.id)
      student = insert(:student, school_id: school.id)
      course = insert(:course, school_id: school.id, teacher_id: teacher.id, title: "Math")

      changesets =
        Actions.submit_grade_change(course, %{score: 7, student_id: student.id}, @authority)

      assert %Ecto.Changeset{} = changesets.grade
      assert changesets.grade.changes.score == 7
      assert changesets.grade.action == :validate
      assert %Ecto.Changeset{} = changesets.course
      assert changesets.course.changes.title == "Math (graded)"
    end

    test "change/3 does not commit" do
      course = insert(:course)
      student = insert(:student, school_id: course.school_id)

      changesets =
        Actions.submit_grade_change(course, %{score: 7, student_id: student.id}, @authority)

      assert Map.has_key?(changesets, :grade)
      assert Repo.all(Grade) == []
      assert Repo.get!(Videdal.Course, course.id).title == course.title
    end

    test "change/3 surfaces invalid params without committing" do
      course = insert(:course)

      changesets = Actions.submit_grade_change(course, %{score: nil, student_id: nil}, @authority)

      refute changesets.grade.valid?
      assert Repo.all(Grade) == []
    end

    test "run/3 commits both writes in one transaction" do
      school = insert(:school)
      teacher = insert(:teacher, school_id: school.id)
      student = insert(:student, school_id: school.id)
      course = insert(:course, school_id: school.id, teacher_id: teacher.id, title: "Math")

      {:ok, results} =
        Actions.submit_grade_run(course, %{score: 7, student_id: student.id}, @authority)

      assert %Grade{score: 7} = results.grade
      assert %Course{title: "Math (graded)"} = results.course
      assert Repo.get!(Course, course.id).title == "Math (graded)"
    end

    test "run/3 rolls back both writes when one step fails" do
      school = insert(:school)
      teacher = insert(:teacher, school_id: school.id)
      course = insert(:course, school_id: school.id, teacher_id: teacher.id, title: "Math")

      result = Actions.submit_grade_run(course, %{score: 7, student_id: nil}, @authority)

      assert {:error, :grade, _context, _prior} = result
      assert Repo.all(Grade) == []
      assert Repo.get!(Course, course.id).title == "Math"
    end
  end

  describe "Hawk.Actions.dispatch/5 (JSON:API path)" do
    test "dispatch routes to the generated submit_grade_run/3 commit" do
      school = insert(:school)
      teacher = insert(:teacher, school_id: school.id)
      student = insert(:student, school_id: school.id)
      course = insert(:course, school_id: school.id, teacher_id: teacher.id, title: "Math")

      {:ok, results} =
        Hawk.Actions.dispatch(
          Videdal.Courses,
          "submit-grade",
          course,
          %{"score" => 7, "student_id" => student.id},
          @authority
        )

      assert %Grade{score: 7} = results.grade
      assert Repo.get!(Course, course.id).title == "Math (graded)"
    end

    test "dispatch still routes run-only actions (open-registration) to their hand-written handler" do
      course =
        insert(:course,
          school_id: insert(:school).id,
          teacher_id: insert(:teacher).id,
          registration_state: "draft",
          seat_count: 0,
          waitlist_count: 0
        )

      {:ok, result} =
        Hawk.Actions.dispatch(
          Videdal.Courses,
          "open-registration",
          course,
          %{"seat_count" => 2, "waitlist_count" => 1},
          @authority
        )

      assert result.registration_state == "open"
    end
  end
end
