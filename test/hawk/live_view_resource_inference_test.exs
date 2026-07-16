defmodule Hawk.LiveViewResourceInferenceTest.Course do
  use Hawk.Model

  model "live_view_resource_inference_courses" do
    field(:title, :string)
  end
end

defmodule Hawk.LiveViewResourceInferenceTest.Courses.Reader do
  def one(opts),
    do: {:ok, %Hawk.LiveViewResourceInferenceTest.Course{id: opts[:filter].id, title: "Math"}}

  def one!(_opts), do: raise("not used")

  def all(_opts),
    do: [%Hawk.LiveViewResourceInferenceTest.Course{id: Videdal.course_id(), title: "Math"}]
end

defmodule Hawk.LiveViewResourceInferenceTest.Courses.Policy do
  def read_filter(_authority), do: :all
end

defmodule Hawk.LiveViewResourceInferenceTest.Courses.JsonApi do
  def __hawk_json_api__, do: %{type: "courses"}
end

defmodule Hawk.LiveViewResourceInferenceTest.Courses.LiveView do
  def __hawk_live_view__, do: %{surfaces: []}
end

defmodule Hawk.LiveViewResourceInferenceTest.Courses do
  use Hawk.Resource,
    model: Hawk.LiveViewResourceInferenceTest.Course,
    writer: false
end

defmodule Hawk.LiveViewResourceInferenceTest.CourseLive do
  use Hawk.LiveView,
    resource: Hawk.LiveViewResourceInferenceTest.Courses
end

defmodule Hawk.LiveViewResourceInferenceTest do
  use ExUnit.Case, async: true

  alias Hawk.LiveViewResourceInferenceTest.CourseLive

  test "LiveView infers assign names from Hawk.Resource model" do
    socket = CourseLive.assign_index(socket(), Hawk.Authority.system())

    assert [%{id: id}] = socket.assigns.courses
    assert id == Videdal.course_id()
    assert socket.assigns.hawk_resource == :course
  end

  test "show helper uses inferred singular assign" do
    socket = CourseLive.assign_show(socket(), Hawk.Authority.system(), Videdal.course_id())

    assert socket.assigns.course.id == Videdal.course_id()
    assert socket.assigns.hawk_resource == :course
  end

  defp socket, do: %{assigns: %{}}
end
