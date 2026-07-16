defmodule Hawk.LiveViewAdapterContractTest.Course do
  use Hawk.Model

  model "live_view_adapter_contract_courses" do
    field(:title, :string)
  end
end

defmodule Hawk.LiveViewAdapterContractTest.Courses.Reader do
  def one(opts),
    do: {:ok, %Hawk.LiveViewAdapterContractTest.Course{id: opts[:filter].id, title: "Math"}}

  def one!(_opts), do: raise("not used")

  def all(_opts),
    do: [%Hawk.LiveViewAdapterContractTest.Course{id: Videdal.course_id(), title: "Math"}]
end

defmodule Hawk.LiveViewAdapterContractTest.Courses.Policy do
  def read_filter(_authority), do: :all
end

defmodule Hawk.LiveViewAdapterContractTest.Courses.JsonApi do
  def __hawk_json_api__, do: %{type: "courses"}
end

defmodule Hawk.LiveViewAdapterContractTest.Courses.LiveView do
  use Hawk.LiveView.Resource

  as(:class)
  plural_as(:classes)
end

defmodule Hawk.LiveViewAdapterContractTest.Courses do
  use Hawk.Resource,
    model: Hawk.LiveViewAdapterContractTest.Course,
    writer: false
end

defmodule Hawk.LiveViewAdapterContractTest.CourseLive do
  use Hawk.LiveView,
    resource: Hawk.LiveViewAdapterContractTest.Courses
end

defmodule Hawk.LiveViewAdapterContractTest do
  use ExUnit.Case, async: true

  alias Hawk.LiveViewAdapterContractTest.CourseLive

  test "LiveView helper infers assigns from LiveView adapter contract" do
    socket = CourseLive.assign_index(socket(), Hawk.Authority.system())

    assert [%{id: id}] = socket.assigns.classes
    assert id == Videdal.course_id()
    assert socket.assigns.hawk_resource == :class
    refute Map.has_key?(socket.assigns, :courses)
  end

  test "show helper uses adapter singular assign" do
    socket = CourseLive.assign_show(socket(), Hawk.Authority.system(), Videdal.course_id())

    assert socket.assigns.class.id == Videdal.course_id()
    assert socket.assigns.hawk_resource == :class
    refute Map.has_key?(socket.assigns, :course)
  end

  defp socket, do: %{assigns: %{}}
end
