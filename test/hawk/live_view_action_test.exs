defmodule Hawk.LiveViewActionTest do
  use Videdal.DatabaseCase, async: true

  import Hawk.TestSocket, only: [socket: 0]

  alias Hawk.Authority
  alias Hawk.LiveView
  alias Videdal.{Course, Grade, Repo}

  @authority Authority.system()

  test "hawk_validate_action validates both writers without committing" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)
    student = insert(:student, school_id: school.id)
    course = insert(:course, school_id: school.id, teacher_id: teacher.id, title: "Math")

    {:noreply, socket} =
      LiveView.hawk_validate_action(
        socket(),
        Videdal.Courses,
        "submit-grade",
        course,
        %{"score" => 7, "student_id" => student.id},
        authority: @authority
      )

    assert %Ecto.Changeset{} = socket.assigns.hawk_action_changesets.grade
    assert socket.assigns.hawk_action_changesets.grade.changes.score == 7
    assert socket.assigns.hawk_action_changesets.course.changes.title == "Math (graded)"
    # Nothing persisted during validation.
    assert Repo.all(Grade) == []
  end

  test "hawk_action commits both writes in one transaction and on_success sees both results" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)
    student = insert(:student, school_id: school.id)
    course = insert(:course, school_id: school.id, teacher_id: teacher.id, title: "Math")

    {:noreply, socket} =
      socket()
      |> Phoenix.Component.assign(:hawk_authority, @authority)
      |> LiveView.hawk_action(
        Videdal.Courses,
        "submit-grade",
        course,
        %{"score" => 7, "student_id" => student.id},
        on_success: fn socket, results ->
          send(self(), {:navigated, results.grade.id})
          socket
        end
      )

    assert_received {:navigated, grade_id}
    assert socket.assigns.hawk_action_results.grade.id == grade_id
    assert %Grade{score: 7} = Repo.get!(Grade, grade_id)
    assert Repo.get!(Course, course.id).title == "Math (graded)"
  end

  test "hawk_action surfaces invalid params without partial commits" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)
    course = insert(:course, school_id: school.id, teacher_id: teacher.id, title: "Math")

    {:noreply, socket} =
      LiveView.hawk_action(
        socket() |> Phoenix.Component.assign(:hawk_authority, @authority),
        Videdal.Courses,
        "submit-grade",
        course,
        %{"score" => 7, "student_id" => nil}
      )

    assert socket.assigns.hawk_error
    assert Repo.all(Grade) == []
    assert Repo.get!(Course, course.id).title == "Math"
  end

  test "hawk_action reads the authority from socket.assigns.hawk_authority by default" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)
    student = insert(:student, school_id: school.id)
    course = insert(:course, school_id: school.id, teacher_id: teacher.id, title: "Math")

    {:noreply, _socket} =
      socket()
      |> Phoenix.Component.assign(:hawk_authority, @authority)
      |> LiveView.hawk_action(
        Videdal.Courses,
        "submit-grade",
        course,
        %{"score" => 8, "student_id" => student.id}
      )

    assert [grade] = Repo.all(Grade)
    assert grade.score == 8
  end
end
