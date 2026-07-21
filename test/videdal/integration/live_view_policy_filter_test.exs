defmodule Videdal.Integration.LiveViewPolicyFilterTest do
  use Videdal.DatabaseCase, async: false

  alias Hawk.Authority
  alias Videdal.{Course, SandboxRepo, School, Teacher}
  alias Videdal.LiveViews.PolicyCheckedCoursesLive

  setup do
    Videdal.DatabaseCase.reset_schema!()

    school = SandboxRepo.insert!(%School{name: "Videdal Skole"})
    teacher = SandboxRepo.insert!(%Teacher{name: "Ms. Curie", school_id: school.id})
    other_teacher = SandboxRepo.insert!(%Teacher{name: "Mr. Feynman", school_id: school.id})

    own_course =
      SandboxRepo.insert!(%Course{title: "Math", school_id: school.id, teacher_id: teacher.id})

    other_course =
      SandboxRepo.insert!(%Course{
        title: "Physics",
        school_id: school.id,
        teacher_id: other_teacher.id
      })

    %{
      school: school,
      teacher: teacher,
      other_teacher: other_teacher,
      own_course: own_course,
      other_course: other_course
    }
  end

  test "LiveView filter params narrow without widening policy visibility", data do
    authority =
      Authority.new(:teacher, data.teacher.id, scopes: %{school_id: data.school.id, teacher_id: data.teacher.id})

    socket =
      PolicyCheckedCoursesLive.assign_index(socket(), authority,
        params: %{"filter" => %{"teacher_id" => data.other_teacher.id}}
      )

    assert socket.assigns.courses == []
  end

  test "LiveView filter params still return visible rows when they match policy", data do
    authority =
      Authority.new(:teacher, data.teacher.id, scopes: %{school_id: data.school.id, teacher_id: data.teacher.id})

    socket =
      PolicyCheckedCoursesLive.assign_index(socket(), authority,
        params: %{"filter" => %{"teacher_id" => data.teacher.id}}
      )

    assert [%Course{id: id, title: "Math"}] = socket.assigns.courses
    assert id == data.own_course.id
  end

  defp socket, do: %{assigns: %{}}
end
