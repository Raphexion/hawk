defmodule Hawk.LiveViewPageTest.CourseWorkspaceLive do
  @moduledoc false

  use Hawk.LiveView.Page,
    resources: [
      course: [resource: Videdal.Courses],
      students: [resource: Videdal.Students],
      grades: [resource: Videdal.Grades]
    ],
    sections: [
      basics: [label: "Basics", path: "/courses/:id"],
      students: [label: "Students", path: "/courses/:id/students"],
      grades: [label: "Grades", path: "/courses/:id/grades"]
    ]
end

defmodule Hawk.LiveViewPageTest do
  use Videdal.DatabaseCase, async: true

  import Hawk.TestSocket, only: [socket: 0]

  alias Hawk.Authority
  alias Hawk.LiveViewPageTest.CourseWorkspaceLive
  alias Videdal.{Grade, Repo}

  @grade_id Videdal.grade_id()

  test "assign_page composes one resource and related collections into one LiveView socket" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)
    course = insert(:course, school_id: school.id, teacher_id: teacher.id, title: "Math")
    other_course = insert(:course, school_id: school.id, teacher_id: teacher.id, title: "Other")
    student = insert(:student, school_id: school.id, name: "Ada")

    grade =
      insert(:grade,
        school_id: school.id,
        student_id: student.id,
        course_id: course.id,
        score: 12
      )

    insert(:grade,
      school_id: school.id,
      student_id: student.id,
      course_id: other_course.id,
      score: 5
    )

    authority =
      Authority.new(:teacher, teacher.id, scopes: %{school_id: school.id, teacher_id: teacher.id})

    socket =
      CourseWorkspaceLive.assign_page(socket(), authority,
        course: {:one, filter: %{id: course.id}, preloads: [:teacher]},
        students: {:all, filter: %{school_id: school.id}, sort: [{:asc, :id}]},
        grades: {:all, filter: %{course_id: course.id}, preloads: [:student]}
      )

    assert socket.assigns.course.id == course.id
    assert socket.assigns.course.title == "Math"
    assert socket.assigns.course.teacher.id == teacher.id

    assert [page_student] = socket.assigns.students
    assert page_student.id == student.id

    assert [page_grade] = socket.assigns.grades
    assert page_grade.id == grade.id
    assert page_grade.score == 12
    assert page_grade.student.id == student.id

    assert socket.assigns.hawk_page_resources == [:course, :students, :grades]

    assert socket.assigns.hawk_page_specs[:grades] ==
             {:all, [filter: %{course_id: course.id}, preloads: [:student]]}
  end

  test "page modules expose workspace navigation metadata" do
    assert CourseWorkspaceLive.hawk_page_sections() == [
             %{id: :basics, label: "Basics", path: "/courses/:id"},
             %{id: :students, label: "Students", path: "/courses/:id/students"},
             %{id: :grades, label: "Grades", path: "/courses/:id/grades"}
           ]

    assert CourseWorkspaceLive.hawk_page_section(:students) == %{
             id: :students,
             label: "Students",
             path: "/courses/:id/students"
           }
  end

  test "assign_page records per-resource errors without stopping other resources" do
    school = insert(:school)
    student = insert(:student, school_id: school.id, name: "Ada")
    authority = Authority.system()

    socket =
      CourseWorkspaceLive.assign_page(socket(), authority,
        course: {:one, filter: %{id: Videdal.other_course_id()}},
        students: {:all, filter: %{school_id: school.id}}
      )

    assert [page_student] = socket.assigns.students
    assert page_student.id == student.id
    assert socket.assigns.hawk_errors == %{course: %{base: ["course was not found"]}}
  end

  test "delete event can target a related page resource and refresh the composed page" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)
    student = insert(:student, school_id: school.id)
    course = insert(:course, school_id: school.id, teacher_id: teacher.id)

    grade =
      insert(:grade,
        school_id: school.id,
        student_id: student.id,
        course_id: course.id,
        score: 12
      )

    authority =
      Authority.new(:school_admin, Videdal.school_admin_id(), scopes: %{school_id: school.id})

    socket =
      CourseWorkspaceLive.assign_page(socket(), authority, grades: {:all, filter: %{course_id: course.id}})

    assert [page_grade] = socket.assigns.grades
    assert page_grade.id == grade.id

    {:noreply, socket} =
      CourseWorkspaceLive.handle_event(
        "hawk:delete",
        %{
          "resource" => "grades",
          "id" => grade.id,
          "authority" => Authority.new(:student, student.id)
        },
        socket
      )

    assert socket.assigns.grades == []
    refute Repo.get(Grade, grade.id)
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
