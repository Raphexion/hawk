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

  test "assign_index loads resources into predictable plural assigns" do
    courses = [%Course{id: 1, title: "Math"}]
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
    course = %Course{id: 3, title: "Math"}
    Process.put({Videdal.Repo, :all_results}, [course])

    socket = CourseShowLive.assign_show(socket(), Authority.system(), 3)

    assert socket.assigns.course == course
    assert socket.assigns.hawk_resource == :course
    assert_received {:videdal_repo, :all, query}
    assert inspect(query) =~ "c0.id == ^3"
  end

  test "assign_show stores a LiveView-friendly error when the record is missing" do
    Process.put({Videdal.Repo, :all_results}, [])

    socket = CourseShowLive.assign_show(socket(), Authority.system(), 404)

    assert socket.assigns.hawk_error == %{base: ["course was not found"]}
  end

  test "assign_show merges an existing filter when loading one resource" do
    course = %Course{id: 3, title: "Math", school_id: 7}
    Process.put({Videdal.Repo, :all_results}, [course])

    socket =
      CourseShowLive.assign_show(socket(), Authority.system(), "external-3",
        filter: %{school_id: 7}
      )

    assert socket.assigns.course == course
    assert_received {:videdal_repo, :all, query}
    inspected = inspect(query)
    assert inspected =~ "c0.school_id == ^7"
    assert inspected =~ ~s(c0.id == ^"external-3")
  end

  test "delete event deletes the resource and refreshes the index assign" do
    course = %Course{id: 3, title: "Math"}
    Process.put({Videdal.Repo, :all_results}, [course])

    {:noreply, socket} =
      CourseIndexLive.handle_event(
        "hawk:delete",
        %{"id" => "3", "authority" => Authority.new(:school_admin, 1, scopes: %{school_id: 7})},
        socket()
      )

    assert socket.assigns.courses == [course]
    assert_received {:videdal_repo, :delete, %Course{id: 3}}
  end

  test "delete event stores a LiveView-friendly not found error" do
    Process.put({Videdal.Repo, :all_results}, [])

    {:noreply, socket} =
      CourseIndexLive.handle_event(
        "hawk:delete",
        %{"id" => "missing", "authority" => Authority.system()},
        socket()
      )

    assert socket.assigns.hawk_error == %{base: ["course was not found"]}
  end

  test "delete event stores LiveView-friendly authorization errors" do
    course = %Course{id: 3, title: "Math", school_id: 7}
    Process.put({Videdal.Repo, :all_results}, [course])

    {:noreply, socket} =
      CourseIndexLive.handle_event(
        "hawk:delete",
        %{"id" => "3", "authority" => Authority.new(:student, 1, scopes: %{school_id: 7})},
        socket()
      )

    assert socket.assigns.hawk_error == %{base: ["You are not allowed to delete this course."]}
  end

  defp socket do
    %{assigns: %{}}
  end
end
