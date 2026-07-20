defmodule Hawk.LiveViewResourceTest.CourseLiveView do
  use Hawk.LiveView.Resource

  as(:class)
  plural_as(:classes)

  index do
    doc("Courses shown to teachers.")
    filter(:teacher_id)
    search(:title, operator: :ilike)
    sort(:id)
    sort(:title)

    table do
      column(:title, label: "Course")
      column(:registration_state)
    end
  end

  show do
    field(:title)
    field(:registration_state, label: "State")
  end

  create_form do
    field(:title, label: gettext("Course"))
    field(:teacher_id)
  end

  update_form do
    field(:title, label: "Course")
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
             index: %{
               doc: "Courses shown to teachers.",
               filters: [:teacher_id],
               searches: [%{name: :title, operator: :ilike}],
               sorts: [:id, :title],
               table: [
                 %{name: :title, label: "Course"},
                 %{name: :registration_state}
               ]
             },
             show: %{
               fields: [
                 %{name: :title},
                 %{name: :registration_state, label: "State"}
               ]
             },
             create_form: %{
               fields: [
                 %{name: :title, label: {:gettext, "Course"}},
                 %{name: :teacher_id}
               ]
             },
             update_form: %{
               fields: [
                 %{name: :title, label: "Course"}
               ]
             }
           }
  end

  test "empty LiveView adapter has explicit empty index and show contracts" do
    assert EmptyLiveView.__hawk_live_view__() == %{
             index: %{},
             show: %{},
             create_form: %{},
             update_form: %{}
           }
  end
end
