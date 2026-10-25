defmodule Hawk.LiveViewComposedTest.WorkspaceLive do
  @moduledoc false

  use Hawk.LiveView.Page,
    resources: [
      course: [resource: Videdal.Courses],
      grades: [resource: Videdal.Grades],
      announcements: [resource: Videdal.ScopedAnnouncements]
    ]
end

defmodule Hawk.LiveViewComposedTest do
  use Videdal.DatabaseCase, async: false

  import Hawk.TestSocket, only: [socket: 0]

  alias Hawk.{Authority, PubSub}
  alias Hawk.LiveViewComposedTest.WorkspaceLive
  alias Videdal.{Course, Grade, Repo, ScopedAnnouncements}

  test "refreshes only the declared resource and preserves its read spec" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)
    course = insert(:course, school_id: school.id, teacher_id: teacher.id, title: "Math")

    socket =
      WorkspaceLive.assign_page(socket(), Authority.system(),
        course: {:one, filter: %{id: course.id}},
        grades: {:all, filter: %{course_id: course.id}}
      )

    Repo.update_all(Course, set: [title: "History"])

    event = %PubSub.Event{resource: Videdal.Courses, operation: :update, identity: :id, identity_value: course.id}

    assert {:ok, %{key: :course, mode: :record, value: %Course{title: "History"}}} =
             Hawk.LiveView.Composed.refresh(socket, WorkspaceLive, event)

    assert {:ignore, :undeclared_resource} =
             Hawk.LiveView.Composed.refresh(
               socket,
               WorkspaceLive,
               %PubSub.Event{resource: Videdal.Students, operation: :update}
             )
  end

  test "re-reads through the socket authority and hides inaccessible records" do
    school_a = insert(:school)
    school_b = insert(:school)
    course_b = insert(:course, school_id: school_b.id, teacher_id: insert(:teacher, school_id: school_b.id).id)

    socket =
      WorkspaceLive.assign_page(
        socket(),
        Authority.new(:school_admin, Videdal.school_admin_id(), scopes: %{school_id: school_a.id}),
        course: {:one, filter: %{id: course_b.id}}
      )

    event = %PubSub.Event{resource: Videdal.Courses, operation: :update, identity: :id, identity_value: course_b.id}

    assert {:ok, %{key: :course, value: :not_found}} =
             Hawk.LiveView.Composed.refresh(socket, WorkspaceLive, event)
  end

  test "returns refreshed collections for application-owned stream resets" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)
    course = insert(:course, school_id: school.id, teacher_id: teacher.id)
    student = insert(:student, school_id: school.id)
    grade = insert(:grade, school_id: school.id, course_id: course.id, student_id: student.id, score: 10)

    socket =
      WorkspaceLive.assign_page(socket(), Authority.system(), grades: {:all, filter: %{course_id: course.id}})

    event = %PubSub.Event{resource: Videdal.Grades, operation: :create, identity: :id, identity_value: grade.id}

    assert {:ok, %{key: :grades, mode: :collection, value: grades}} =
             Hawk.LiveView.Composed.refresh(socket, WorkspaceLive, event)

    assert Enum.map(grades, & &1.id) == [grade.id]
  end

  test "supports paginated page specs and returns page metadata on refresh" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)
    course = insert(:course, school_id: school.id, teacher_id: teacher.id)
    student = insert(:student, school_id: school.id)
    grade = insert(:grade, school_id: school.id, course_id: course.id, student_id: student.id, score: 10)
    grade_id = grade.id

    socket =
      WorkspaceLive.assign_page(socket(), Authority.system(),
        grades: {:page, filter: %{course_id: course.id}, page: %{size: 1}}
      )

    assert [%Grade{id: ^grade_id}] = socket.assigns.grades
    assert %Hawk.Reader.Page{} = socket.assigns.hawk_page_metadata.grades

    event = %PubSub.Event{resource: Videdal.Grades, operation: :update, identity: :id, identity_value: grade.id}

    assert {:ok, %{key: :grades, mode: :page, value: %Hawk.Reader.Page{entries: [%Grade{id: ^grade_id}]}}} =
             Hawk.LiveView.Composed.refresh(socket, WorkspaceLive, event)
  end

  test "subscribes each declared resource using its configured topic strategy" do
    school = insert(:school)

    socket =
      socket()
      |> Phoenix.Component.assign(:current_school_id, school.id)
      |> Hawk.LiveView.Composed.subscribe(WorkspaceLive)

    assert is_struct(socket, Phoenix.LiveView.Socket)

    assert {:ok, _} =
             ScopedAnnouncements.create(%{body: "Visible", school_id: school.id}, Authority.system())

    assert_receive %PubSub.Event{resource: Videdal.ScopedAnnouncements}
  end
end
