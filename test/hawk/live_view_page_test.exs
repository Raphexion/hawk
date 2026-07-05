defmodule Hawk.LiveViewPageTest.CourseWorkspaceLive do
  @moduledoc false

  use Hawk.LiveView.Page,
    resources: [
      course: [resource: Videdal.Courses],
      students: [resource: Videdal.Students],
      grades: [resource: Videdal.Grades]
    ]
end

defmodule Hawk.LiveViewPageTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Hawk.LiveViewPageTest.CourseWorkspaceLive
  alias Videdal.{Course, Grade, Student}

  test "assign_page composes one resource and related collections into one LiveView socket" do
    authority = Authority.new(:teacher, 12, scopes: %{school_id: 7, teacher_id: 12})
    course = %Course{id: 3, title: "Math", school_id: 7, teacher_id: 12}
    students = [%Student{id: 8, name: "Ada", school_id: 7}]
    grades = [%Grade{id: 1, score: 12, school_id: 7, student_id: 8, course_id: 3}]

    Process.put({Videdal.Repo, :all_results, Videdal.Course}, [course])
    Process.put({Videdal.Repo, :all_results, Videdal.Student}, students)
    Process.put({Videdal.Repo, :all_results, Videdal.Grade}, grades)

    socket =
      CourseWorkspaceLive.assign_page(socket(), authority,
        course: {:one, filter: %{id: 3}, preloads: [:teacher]},
        students: {:all, filter: %{school_id: 7}, page: %{column: :id, dir: :asc}},
        grades: {:all, filter: %{course_id: 3}, preloads: [:student]}
      )

    assert socket.assigns.course == course
    assert socket.assigns.students == students
    assert socket.assigns.grades == grades
    assert socket.assigns.hawk_page_resources == [:course, :students, :grades]

    assert socket.assigns.hawk_page_specs[:grades] ==
             {:all, [filter: %{course_id: 3}, preloads: [:student]]}

    assert_received {:videdal_repo, :all, course_query}
    assert inspect(course_query) =~ "c0.id == ^3"

    assert_received {:videdal_repo, :all, student_query}
    assert inspect(student_query) =~ "s0.school_id == ^7"

    assert_received {:videdal_repo, :all, grade_query}
    assert inspect(grade_query) =~ "g0.course_id == ^3"
  end

  test "assign_page records per-resource errors without stopping other resources" do
    authority = Authority.system()
    students = [%Student{id: 8, name: "Ada", school_id: 7}]

    Process.put({Videdal.Repo, :all_results, Videdal.Course}, [])
    Process.put({Videdal.Repo, :all_results, Videdal.Student}, students)

    socket =
      CourseWorkspaceLive.assign_page(socket(), authority,
        course: {:one, filter: %{id: 404}},
        students: {:all, filter: %{school_id: 7}}
      )

    assert socket.assigns.students == students
    assert socket.assigns.hawk_errors == %{course: %{base: ["course was not found"]}}
  end

  test "delete event can target a related page resource and refresh the composed page" do
    authority = Authority.new(:school_admin, 1, scopes: %{school_id: 7})
    grade = %Grade{id: 1, score: 12, school_id: 7, student_id: 8, course_id: 3}

    Process.put({Videdal.Repo, :all_results, Videdal.Grade}, [grade])

    socket =
      CourseWorkspaceLive.assign_page(socket(), authority,
        grades: {:all, filter: %{course_id: 3}}
      )

    {:noreply, socket} =
      CourseWorkspaceLive.handle_event(
        "hawk:delete",
        %{"resource" => "grades", "id" => "1", "authority" => Authority.new(:student, 99)},
        socket
      )

    assert socket.assigns.grades == [grade]
    assert_received {:videdal_repo, :delete, %Grade{id: 1}}
  end

  test "delete event rejects declared resources that are not active on this page instance" do
    authority = Authority.system()

    socket =
      CourseWorkspaceLive.assign_page(socket(), authority, course: {:one, filter: %{id: 404}})

    assert_raise ArgumentError, ~r/resource :grades is not active/, fn ->
      CourseWorkspaceLive.handle_event(
        "hawk:delete",
        %{"resource" => "grades", "id" => "1"},
        socket
      )
    end
  end

  defp socket, do: %{assigns: %{}}
end
