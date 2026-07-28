defmodule Videdal.LiveViews.CourseLiveTest do
  use Videdal.DatabaseCase, async: true

  import Hawk.TestSocket, only: [socket: 0]

  alias Hawk.Authority
  alias Videdal.Course
  alias Videdal.LiveViews.{CourseCustomSaveLive, CourseLive}
  alias Videdal.Repo

  test "default course LiveView validates and saves through generated events" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)
    school_id = school.id
    teacher_id = teacher.id

    socket = CourseLive.assign_new_form(socket(), Authority.system())

    {:noreply, socket} =
      CourseLive.handle_event("hawk:validate", %{"course" => %{"title" => ""}}, socket)

    assert errors_on(socket.assigns.course_form).title == ["can't be blank"]

    {:noreply, socket} =
      CourseLive.handle_event(
        "hawk:save",
        %{
          "course" => %{
            "title" => "History",
            "school_id" => school.id,
            "teacher_id" => teacher.id
          }
        },
        socket
      )

    assert %Course{title: "History", school_id: ^school_id, teacher_id: ^teacher_id} =
             socket.assigns.course

    assert socket.assigns.hawk_form_states.course.mode == :update

    assert %Course{title: "History"} = Repo.get!(Course, socket.assigns.course.id)
  end

  test "custom save example reuses Hawk helpers and owns post-save navigation" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)
    course = insert(:course, school_id: school.id, teacher_id: teacher.id, title: "Math")

    socket = CourseCustomSaveLive.assign_edit_form(socket(), course, Authority.system())

    {:noreply, socket} =
      CourseCustomSaveLive.handle_event(
        "hawk:save",
        %{"course" => %{"title" => "History"}},
        socket
      )

    course_id = course.id
    assert %Course{id: ^course_id, title: "History"} = socket.assigns.course
    assert socket.navigated_to == "/courses/#{course.id}"

    assert %Course{title: "History"} = Repo.get!(Course, course.id)
  end

  defp errors_on(%Phoenix.HTML.Form{source: changeset}), do: errors_on(changeset)

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
