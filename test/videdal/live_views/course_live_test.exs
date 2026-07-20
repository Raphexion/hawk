defmodule Videdal.LiveViews.CourseLiveTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Videdal.Course
  alias Videdal.LiveViews.{CourseCustomSaveLive, CourseLive}

  @course_id Videdal.course_id()
  @school_id Videdal.school_id()
  @teacher_id Videdal.teacher_id()

  test "default course LiveView validates and saves through generated events" do
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
            "school_id" => @school_id,
            "teacher_id" => @teacher_id
          }
        },
        socket
      )

    assert %Course{title: "History", school_id: @school_id, teacher_id: @teacher_id} =
             socket.assigns.course

    assert socket.assigns.hawk_form_states.course.mode == :update
    assert_received {:videdal_repo, :insert, %Ecto.Changeset{valid?: true}}
  end

  test "custom save example reuses Hawk helpers and owns post-save navigation" do
    course = %Course{
      id: @course_id,
      title: "Math",
      school_id: @school_id,
      teacher_id: @teacher_id
    }

    socket = CourseCustomSaveLive.assign_edit_form(socket(), course, Authority.system())

    {:noreply, socket} =
      CourseCustomSaveLive.handle_event(
        "hawk:save",
        %{"course" => %{"title" => "History"}},
        socket
      )

    assert %Course{id: @course_id, title: "History"} = socket.assigns.course
    assert socket.navigated_to == "/courses/#{@course_id}"
    assert_received {:videdal_repo, :update, %Ecto.Changeset{valid?: true}}
  end

  defp socket, do: %{assigns: %{}}

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
