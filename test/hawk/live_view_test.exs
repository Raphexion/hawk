defmodule Hawk.LiveViewTest.CourseIndexLive do
  @moduledoc false

  use Hawk.LiveView,
    resource: Videdal.Courses,
    as: :course
end

defmodule Hawk.LiveViewTest.CourseShowLive do
  @moduledoc false

  use Hawk.LiveView,
    resource: Videdal.Courses,
    as: :course
end

defmodule Hawk.LiveViewTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Hawk.LiveViewTest.{CourseIndexLive, CourseShowLive}
  alias Videdal.Course

  @course_id Videdal.course_id()
  @other_course_id Videdal.other_course_id()
  @school_admin_id Videdal.school_admin_id()
  @school_id Videdal.school_id()
  @student_id Videdal.student_id()

  test "assign_index loads resources into predictable plural assigns" do
    courses = [%Course{id: @course_id, title: "Math"}]
    Process.put({Videdal.Repo, :all_results}, courses)

    socket =
      CourseIndexLive.assign_index(socket(), Authority.system(),
        page: %{column: :title, dir: :asc, size: 10}
      )

    assert socket.assigns.courses == courses
    assert socket.assigns.hawk_resource == :course
    assert socket.assigns.hawk_page == %{column: :title, dir: :asc, size: 10}
    assert_received {:videdal_repo, :all, query}
    assert inspect(query) =~ "order_by: [asc: c0.title]"
  end

  test "assign_show loads one resource into predictable singular assigns" do
    course = %Course{id: @course_id, title: "Math"}
    Process.put({Videdal.Repo, :all_results}, [course])

    socket = CourseShowLive.assign_show(socket(), Authority.system(), @course_id)

    assert socket.assigns.course == course
    assert socket.assigns.hawk_resource == :course
    assert_received {:videdal_repo, :all, query}
    assert inspect(query) =~ "c0.id == ^\"#{@course_id}\""
  end

  test "assign_show stores a LiveView-friendly error when the record is missing" do
    Process.put({Videdal.Repo, :all_results}, [])

    socket = CourseShowLive.assign_show(socket(), Authority.system(), @other_course_id)

    assert socket.assigns.hawk_error == %{base: ["course was not found"]}
  end

  test "assign_show merges an existing filter when loading one resource" do
    course = %Course{id: @course_id, title: "Math", school_id: @school_id}
    Process.put({Videdal.Repo, :all_results}, [course])

    socket =
      CourseShowLive.assign_show(socket(), Authority.system(), @course_id,
        filter: %{school_id: @school_id}
      )

    assert socket.assigns.course == course
    assert_received {:videdal_repo, :all, query}
    inspected = inspect(query)
    assert inspected =~ "c0.school_id == ^\"#{@school_id}\""
    assert inspected =~ "c0.id == ^\"#{@course_id}\""
  end

  test "delete event deletes the resource and refreshes the index assign" do
    course = %Course{id: @course_id, title: "Math"}
    Process.put({Videdal.Repo, :all_results}, [course])

    {:noreply, socket} =
      CourseIndexLive.handle_event(
        "hawk:delete",
        %{
          "id" => @course_id,
          "authority" =>
            Authority.new(:school_admin, @school_admin_id, scopes: %{school_id: @school_id})
        },
        socket()
      )

    assert socket.assigns.courses == [course]
    assert_received {:videdal_repo, :delete, %Course{id: @course_id}}
  end

  test "delete event stores a LiveView-friendly not found error" do
    Process.put({Videdal.Repo, :all_results}, [])

    {:noreply, socket} =
      CourseIndexLive.handle_event(
        "hawk:delete",
        %{"id" => @other_course_id, "authority" => Authority.system()},
        socket()
      )

    assert socket.assigns.hawk_error == %{base: ["course was not found"]}
  end

  test "delete event stores LiveView-friendly authorization errors" do
    course = %Course{id: @course_id, title: "Math", school_id: @school_id}
    Process.put({Videdal.Repo, :all_results}, [course])

    {:noreply, socket} =
      CourseIndexLive.handle_event(
        "hawk:delete",
        %{
          "id" => @course_id,
          "authority" => Authority.new(:student, @student_id, scopes: %{school_id: @school_id})
        },
        socket()
      )

    assert socket.assigns.hawk_error == %{base: ["You are not allowed to delete this course."]}
  end

  defp socket do
    %{assigns: %{}}
  end
end
