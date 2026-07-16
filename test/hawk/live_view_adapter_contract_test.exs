defmodule Hawk.LiveViewAdapterContractTest do
  use ExUnit.Case, async: true

  alias Videdal.LiveViews.ExternalCourseLive

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

  defp socket, do: %{assigns: %{}}
end
