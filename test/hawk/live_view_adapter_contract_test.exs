defmodule Hawk.LiveViewAdapterContractTest do
  use ExUnit.Case, async: true

  alias Videdal.LiveViews.{CourseCatalogLive, ExternalCourseLive}

  test "LiveView helper infers assigns from LiveView adapter contract" do
    socket = ExternalCourseLive.assign_index(socket(), Hawk.Authority.system())

    assert [%{id: id}] = socket.assigns.external_courses
    assert id == Videdal.course_id()
    assert socket.assigns.hawk_resource == :external_course
    refute Map.has_key?(socket.assigns, :courses)
  end

  test "show helper uses adapter singular assign" do
    socket =
      ExternalCourseLive.assign_show(socket(), Hawk.Authority.system(), Videdal.course_id())

    assert socket.assigns.external_course.id == Videdal.course_id()
    assert socket.assigns.hawk_resource == :external_course
    refute Map.has_key?(socket.assigns, :course)
  end

  test "LiveView delete handler follows writer capability" do
    Code.ensure_loaded!(ExternalCourseLive)
    Code.ensure_loaded!(CourseCatalogLive)

    assert function_exported?(ExternalCourseLive, :handle_event, 3)
    refute function_exported?(CourseCatalogLive, :handle_event, 3)
  end

  defp socket, do: %{assigns: %{}}
end
