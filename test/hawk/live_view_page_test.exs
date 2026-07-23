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

  import Hawk.TestSocket, only: [socket: 0]

  alias Hawk.Authority
  alias Hawk.LiveViewPageTest.CourseWorkspaceLive
  alias Videdal.{Course, Grade, Student}

  @course_id Videdal.course_id()
  @grade_id Videdal.grade_id()
  @school_admin_id Videdal.school_admin_id()
  @school_id Videdal.school_id()
  @student_id Videdal.student_id()
  @teacher_id Videdal.teacher_id()

  test "assign_page composes one resource and related collections into one LiveView socket" do
    authority =
      Authority.new(:teacher, @teacher_id, scopes: %{school_id: @school_id, teacher_id: @teacher_id})

    course = %Course{
      id: @course_id,
      title: "Math",
      school_id: @school_id,
      teacher_id: @teacher_id
    }

    students = [%Student{id: @student_id, name: "Ada", school_id: @school_id}]

    grades = [
      %Grade{
        id: @grade_id,
        score: 12,
        school_id: @school_id,
        student_id: @student_id,
        course_id: @course_id
      }
    ]

    Process.put({Videdal.Repo, :all_results, Videdal.Course}, [course])
    Process.put({Videdal.Repo, :all_results, Videdal.Student}, students)
    Process.put({Videdal.Repo, :all_results, Videdal.Grade}, grades)

    socket =
      CourseWorkspaceLive.assign_page(socket(), authority,
        course: {:one, filter: %{id: @course_id}, preloads: [:teacher]},
        students: {:all, filter: %{school_id: @school_id}, page: %{column: :id, dir: :asc}},
        grades: {:all, filter: %{course_id: @course_id}, preloads: [:student]}
      )

    assert socket.assigns.course == course
    assert socket.assigns.students == students
    assert socket.assigns.grades == grades
    assert socket.assigns.hawk_page_resources == [:course, :students, :grades]

    assert socket.assigns.hawk_page_specs[:grades] ==
             {:all, [filter: %{course_id: @course_id}, preloads: [:student]]}

    assert_received {:videdal_repo, :all, course_query}
    assert inspect(course_query) =~ "c0.id == ^\"#{@course_id}\""

    assert_received {:videdal_repo, :all, student_query}
    assert inspect(student_query) =~ "s0.school_id == ^\"#{@school_id}\""

    assert_received {:videdal_repo, :all, grade_query}
    assert inspect(grade_query) =~ "g0.course_id == ^\"#{@course_id}\""
  end

  test "assign_page records per-resource errors without stopping other resources" do
    authority = Authority.system()
    students = [%Student{id: @student_id, name: "Ada", school_id: @school_id}]

    Process.put({Videdal.Repo, :all_results, Videdal.Course}, [])
    Process.put({Videdal.Repo, :all_results, Videdal.Student}, students)

    socket =
      CourseWorkspaceLive.assign_page(socket(), authority,
        course: {:one, filter: %{id: Videdal.other_course_id()}},
        students: {:all, filter: %{school_id: @school_id}}
      )

    assert socket.assigns.students == students
    assert socket.assigns.hawk_errors == %{course: %{base: ["course was not found"]}}
  end

  test "delete event can target a related page resource and refresh the composed page" do
    authority = Authority.new(:school_admin, @school_admin_id, scopes: %{school_id: @school_id})

    grade = %Grade{
      id: @grade_id,
      score: 12,
      school_id: @school_id,
      student_id: @student_id,
      course_id: @course_id
    }

    Process.put({Videdal.Repo, :all_results, Videdal.Grade}, [grade])

    socket =
      CourseWorkspaceLive.assign_page(socket(), authority, grades: {:all, filter: %{course_id: @course_id}})

    {:noreply, socket} =
      CourseWorkspaceLive.handle_event(
        "hawk:delete",
        %{
          "resource" => "grades",
          "id" => @grade_id,
          "authority" => Authority.new(:student, @student_id)
        },
        socket
      )

    assert socket.assigns.grades == [grade]
    assert_received {:videdal_repo, :delete, %Grade{id: @grade_id}}
  end

  test "delete event rejects declared resources that are not active on this page instance" do
    authority = Authority.system()

    socket =
      CourseWorkspaceLive.assign_page(socket(), authority, course: {:one, filter: %{id: Videdal.other_course_id()}})

    assert_raise ArgumentError, ~r/resource :grades is not active/, fn ->
      CourseWorkspaceLive.handle_event(
        "hawk:delete",
        %{"resource" => "grades", "id" => @grade_id},
        socket
      )
    end
  end

  test "delete event rejects hostile resource names without creating atoms" do
    hostile = "hawk_hostile_live_view_#{System.unique_integer([:positive])}"
    socket = CourseWorkspaceLive.assign_page(socket(), Authority.system(), [])

    assert_raise ArgumentError, ~r/unknown LiveView page resource/, fn ->
      CourseWorkspaceLive.handle_event(
        "hawk:delete",
        %{"resource" => hostile, "id" => @grade_id},
        socket
      )
    end

    assert_raise ArgumentError, fn -> String.to_existing_atom(hostile) end
  end
end
