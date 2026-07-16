defmodule Hawk.LiveViewResourceTest.CourseLiveView do
  use Hawk.LiveView.Resource

  as(:class)
  plural_as(:classes)

  index :teacher_focus do
    doc("Courses shown to teachers.")
    filter(:teacher_id)

    table do
      column(:title, label: "Course")
      column(:registration_state)
    end
  end

  show :detail do
    field(:title)
    field(:registration_state, label: "State")
  end
end

defmodule Hawk.LiveViewResourceTest.EmptyLiveView do
  use Hawk.LiveView.Resource
end

defmodule Hawk.LiveViewResourceTest do
  use ExUnit.Case, async: true

  alias Hawk.LiveViewResourceTest.{CourseLiveView, EmptyLiveView}

  test "declares LiveView adapter metadata" do
    assert CourseLiveView.__hawk_live_view__() == %{
             as: :class,
             plural_as: :classes,
             surfaces: %{
               index: %{
                 teacher_focus: %{
                   doc: "Courses shown to teachers.",
                   filters: [:teacher_id],
                   table: [
                     %{name: :title, label: "Course"},
                     %{name: :registration_state}
                   ]
                 }
               },
               show: %{
                 detail: %{
                   fields: [
                     %{name: :title},
                     %{name: :registration_state, label: "State"}
                   ]
                 }
               }
             }
           }
  end

  test "empty LiveView adapter has explicit empty surfaces" do
    assert EmptyLiveView.__hawk_live_view__() == %{
             surfaces: %{index: %{}, show: %{}}
           }
  end
end
