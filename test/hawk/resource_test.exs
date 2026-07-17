defmodule Hawk.ResourceTest.Course do
  use Hawk.Model

  model "hawk_resource_test_courses" do
    field(:title, :string)
  end
end

defmodule Hawk.ResourceTest.Courses.Reader do
  def one(opts), do: {:one, opts}
  def one!(opts), do: {:one!, opts}
  def all(opts), do: {:all, opts}
  def filter_keys, do: MapSet.new([:title])
end

defmodule Hawk.ResourceTest.Courses.Policy do
  def read_filter(_authority), do: :all
  def create?(_context), do: true
  def update?(_context), do: true
  def delete?(_context), do: true
end

defmodule Hawk.ResourceTest.Courses.Writer do
  def create(attrs, authority), do: {:create, attrs, authority}
  def update(course, attrs, authority), do: {:update, course, attrs, authority}
  def delete(course, authority), do: {:delete, course, authority}
end

defmodule Hawk.ResourceTest.Courses.JsonApi do
  def __hawk_json_api__, do: %{type: "courses"}
end

defmodule Hawk.ResourceTest.Courses.LiveView do
  use Hawk.LiveView.Resource

  index do
    filter(:title)

    table do
      column(:title)
    end
  end

  show do
    field(:title)
  end
end

defmodule Hawk.ResourceTest.Courses.Actions do
  use Hawk.Actions

  action("open-registration", params: [seat_count: [type: :integer]])

  def open_registration(course, params, authority),
    do: {:open_registration, course, params, authority}
end

defmodule Hawk.ResourceTest.Courses do
  use Hawk.Resource, model: Hawk.ResourceTest.Course
end

defmodule Hawk.ResourceTest.CourseSummaries.Reader do
  def one(opts), do: {:one, opts}
  def one!(opts), do: {:one!, opts}
  def all(opts), do: {:all, opts}
end

defmodule Hawk.ResourceTest.CourseSummaries.Policy do
  def read_filter(_authority), do: :all
end

defmodule Hawk.ResourceTest.CourseSummaries do
  use Hawk.Resource,
    model: Hawk.ResourceTest.Course,
    writer: false,
    json_api: false,
    live_view: false
end

defmodule Hawk.ResourceTest.CustomFacade.CustomReader do
  def one(opts), do: {:custom_one, opts}
  def one!(opts), do: {:custom_one!, opts}
  def all(opts), do: {:custom_all, opts}
end

defmodule Hawk.ResourceTest.CustomFacade.CustomPolicy do
  def read_filter(_authority), do: :none
end

defmodule Hawk.ResourceTest.CustomFacade.CustomJsonApi do
  def __hawk_json_api__, do: %{type: "custom-courses"}
end

defmodule Hawk.ResourceTest.CustomFacade.CustomLiveView do
  def __hawk_live_view__, do: %{index: %{}, show: %{}}
end

defmodule Hawk.ResourceTest.CustomFacade do
  use Hawk.Resource,
    model: Hawk.ResourceTest.Course,
    reader: Hawk.ResourceTest.CustomFacade.CustomReader,
    policy: Hawk.ResourceTest.CustomFacade.CustomPolicy,
    writer: false,
    json_api: Hawk.ResourceTest.CustomFacade.CustomJsonApi,
    live_view: Hawk.ResourceTest.CustomFacade.CustomLiveView
end

defmodule Hawk.ResourceTest do
  use ExUnit.Case, async: true

  alias Hawk.ResourceTest.{Course, Courses, CourseSummaries, CustomFacade}

  test "convention resource facade delegates reader, writer, and actions" do
    authority = Hawk.Authority.system()
    course = %Course{id: Videdal.course_id(), title: "Math"}

    assert Courses.one(authority: authority) == {:one, [authority: authority]}
    assert Courses.one!(authority: authority) == {:one!, [authority: authority]}
    assert Courses.all(authority: authority) == {:all, [authority: authority]}
    assert Courses.create(%{title: "Math"}, authority) == {:create, %{title: "Math"}, authority}

    assert Courses.update(course, %{title: "Science"}, authority) ==
             {:update, course, %{title: "Science"}, authority}

    assert Courses.delete(course, authority) == {:delete, course, authority}

    assert Courses.open_registration(course, %{seat_count: 10}, authority) ==
             {:open_registration, course, %{seat_count: 10}, authority}

    assert Courses.action("open-registration", course, %{seat_count: 10}, authority) ==
             {:open_registration, course, %{seat_count: 10}, authority}
  end

  test "resource facade exposes capability introspection" do
    assert Courses.__hawk_resource__(:model) == Course
    assert Courses.__hawk_resource__(:reader) == Hawk.ResourceTest.Courses.Reader
    assert Courses.__hawk_resource__(:policy) == Hawk.ResourceTest.Courses.Policy
    assert Courses.__hawk_resource__(:writer) == Hawk.ResourceTest.Courses.Writer
    assert Courses.__hawk_resource__(:json_api) == Hawk.ResourceTest.Courses.JsonApi
    assert Courses.__hawk_resource__(:live_view) == Hawk.ResourceTest.Courses.LiveView
    assert Courses.__hawk_resource__(:actions) == Hawk.ResourceTest.Courses.Actions

    assert Courses.__hawk_resource__(:capabilities) == %{
             reader: true,
             writer: true,
             json_api: true,
             live_view: true,
             actions: true
           }
  end

  test "explicit false documents absent capabilities and does not generate writer delegates" do
    assert CourseSummaries.one(authority: Hawk.Authority.system()) ==
             {:one, [authority: Hawk.Authority.system()]}

    assert CourseSummaries.__hawk_resource__(:writer) == false
    assert CourseSummaries.__hawk_resource__(:json_api) == false
    assert CourseSummaries.__hawk_resource__(:live_view) == false
    refute function_exported?(CourseSummaries, :create, 2)
    refute function_exported?(CourseSummaries, :update, 3)
    refute function_exported?(CourseSummaries, :delete, 2)
  end

  test "explicit modules override conventions" do
    assert CustomFacade.all(authority: Hawk.Authority.system()) ==
             {:custom_all, [authority: Hawk.Authority.system()]}

    assert CustomFacade.__hawk_resource__(:reader) == Hawk.ResourceTest.CustomFacade.CustomReader
    assert CustomFacade.__hawk_resource__(:policy) == Hawk.ResourceTest.CustomFacade.CustomPolicy

    assert CustomFacade.__hawk_resource__(:json_api) ==
             Hawk.ResourceTest.CustomFacade.CustomJsonApi

    assert CustomFacade.__hawk_resource__(:live_view) ==
             Hawk.ResourceTest.CustomFacade.CustomLiveView
  end

  test "conventional missing modules fail at compile time unless disabled" do
    assert_raise ArgumentError,
                 ~r/Hawk resource reader module Hawk.ResourceTest.Broken.Reader is not available/,
                 fn ->
                   Code.compile_string("""
                   defmodule Hawk.ResourceTest.Broken do
                     use Hawk.Resource,
                       model: Hawk.ResourceTest.Course,
                       writer: false,
                       json_api: false,
                       live_view: false
                   end
                   """)
                 end
  end

  test "malformed adapter modules fail at compile time" do
    assert_raise ArgumentError,
                 ~r/Hawk resource json_api module Hawk.ResourceTest.Malformed.JsonApi must define __hawk_json_api__\/0/,
                 fn ->
                   Code.compile_string("""
                   defmodule Hawk.ResourceTest.Malformed.Reader do
                     def one(opts), do: {:one, opts}
                     def one!(opts), do: {:one!, opts}
                     def all(opts), do: {:all, opts}
                   end

                   defmodule Hawk.ResourceTest.Malformed.Policy do
                     def read_filter(_authority), do: :all
                   end

                   defmodule Hawk.ResourceTest.Malformed.Writer do
                     def create(attrs, authority), do: {:create, attrs, authority}
                     def update(model, attrs, authority), do: {:update, model, attrs, authority}
                     def delete(model, authority), do: {:delete, model, authority}
                   end

                   defmodule Hawk.ResourceTest.Malformed.JsonApi do
                   end

                   defmodule Hawk.ResourceTest.Malformed.LiveView do
                     def __hawk_live_view__, do: %{}
                   end

                   defmodule Hawk.ResourceTest.Malformed do
                     use Hawk.Resource, model: Hawk.ResourceTest.Course
                   end
                   """)
                 end
  end

  test "json_api attribute sources must reference model fields" do
    assert_raise ArgumentError,
                 ~r/Hawk resource json_api module Hawk.ResourceTest.BadAttributeSource.JsonApi attribute :headline source :missing_title must reference a field on Hawk.ResourceTest.Course/,
                 fn ->
                   Code.compile_string("""
                   defmodule Hawk.ResourceTest.BadAttributeSource.Reader do
                     def one(opts), do: {:one, opts}
                     def one!(opts), do: {:one!, opts}
                     def all(opts), do: {:all, opts}
                   end

                   defmodule Hawk.ResourceTest.BadAttributeSource.Policy do
                     def read_filter(_authority), do: :all
                   end

                   defmodule Hawk.ResourceTest.BadAttributeSource.Writer do
                     def create(attrs, authority), do: {:create, attrs, authority}
                     def update(model, attrs, authority), do: {:update, model, attrs, authority}
                     def delete(model, authority), do: {:delete, model, authority}
                   end

                   defmodule Hawk.ResourceTest.BadAttributeSource.JsonApi do
                     use Hawk.JsonApi.Resource

                     type("courses")
                     attribute(:headline, source: :missing_title)
                   end

                   defmodule Hawk.ResourceTest.BadAttributeSource.LiveView do
                     def __hawk_live_view__, do: %{}
                   end

                   defmodule Hawk.ResourceTest.BadAttributeSource do
                     use Hawk.Resource, model: Hawk.ResourceTest.Course
                   end
                   """)
                 end
  end

  test "json_api relationship sources must reference model associations" do
    assert_raise ArgumentError,
                 ~r/Hawk resource json_api module Hawk.ResourceTest.BadRelationshipSource.JsonApi relationship :teacher source :missing_teacher must reference an association on Hawk.ResourceTest.Course/,
                 fn ->
                   Code.compile_string("""
                   defmodule Hawk.ResourceTest.BadRelationshipSource.Reader do
                     def one(opts), do: {:one, opts}
                     def one!(opts), do: {:one!, opts}
                     def all(opts), do: {:all, opts}
                   end

                   defmodule Hawk.ResourceTest.BadRelationshipSource.Policy do
                     def read_filter(_authority), do: :all
                   end

                   defmodule Hawk.ResourceTest.BadRelationshipSource.Writer do
                     def create(attrs, authority), do: {:create, attrs, authority}
                     def update(model, attrs, authority), do: {:update, model, attrs, authority}
                     def delete(model, authority), do: {:delete, model, authority}
                   end

                   defmodule Hawk.ResourceTest.BadRelationshipSource.JsonApi do
                     use Hawk.JsonApi.Resource

                     type("courses")
                     relationship(:teacher, source: :missing_teacher)
                   end

                   defmodule Hawk.ResourceTest.BadRelationshipSource.LiveView do
                     def __hawk_live_view__, do: %{}
                   end

                   defmodule Hawk.ResourceTest.BadRelationshipSource do
                     use Hawk.Resource, model: Hawk.ResourceTest.Course
                   end
                   """)
                 end
  end

  test "live_view fields must reference model fields" do
    assert_raise ArgumentError,
                 ~r/Hawk resource live_view module Hawk.ResourceTest.BadLiveField.LiveView show field :headline source :missing_title must reference a field on Hawk.ResourceTest.Course/,
                 fn ->
                   Code.compile_string("""
                   defmodule Hawk.ResourceTest.BadLiveField.Reader do
                     def one(opts), do: {:one, opts}
                     def one!(opts), do: {:one!, opts}
                     def all(opts), do: {:all, opts}
                   end

                   defmodule Hawk.ResourceTest.BadLiveField.Policy do
                     def read_filter(_authority), do: :all
                   end

                   defmodule Hawk.ResourceTest.BadLiveField.Writer do
                     def create(attrs, authority), do: {:create, attrs, authority}
                     def update(model, attrs, authority), do: {:update, model, attrs, authority}
                     def delete(model, authority), do: {:delete, model, authority}
                   end

                   defmodule Hawk.ResourceTest.BadLiveField.JsonApi do
                     def __hawk_json_api__, do: %{type: "courses"}
                   end

                   defmodule Hawk.ResourceTest.BadLiveField.LiveView do
                     use Hawk.LiveView.Resource

                     show do
                       field(:headline, source: :missing_title)
                     end
                   end

                   defmodule Hawk.ResourceTest.BadLiveField do
                     use Hawk.Resource, model: Hawk.ResourceTest.Course
                   end
                   """)
                 end
  end

  test "live_view filters must be declared reader filters" do
    assert_raise ArgumentError,
                 ~r/Hawk resource live_view module Hawk.ResourceTest.BadLiveFilter.LiveView index filter :teacher_id must be declared by reader Hawk.ResourceTest.BadLiveFilter.Reader/,
                 fn ->
                   Code.compile_string("""
                   defmodule Hawk.ResourceTest.BadLiveFilter.Reader do
                     def one(opts), do: {:one, opts}
                     def one!(opts), do: {:one!, opts}
                     def all(opts), do: {:all, opts}
                     def filter_keys, do: MapSet.new([:title])
                   end

                   defmodule Hawk.ResourceTest.BadLiveFilter.Policy do
                     def read_filter(_authority), do: :all
                   end

                   defmodule Hawk.ResourceTest.BadLiveFilter.Writer do
                     def create(attrs, authority), do: {:create, attrs, authority}
                     def update(model, attrs, authority), do: {:update, model, attrs, authority}
                     def delete(model, authority), do: {:delete, model, authority}
                   end

                   defmodule Hawk.ResourceTest.BadLiveFilter.JsonApi do
                     def __hawk_json_api__, do: %{type: "courses"}
                   end

                   defmodule Hawk.ResourceTest.BadLiveFilter.LiveView do
                     use Hawk.LiveView.Resource

                     index do
                       filter(:teacher_id)
                     end
                   end

                   defmodule Hawk.ResourceTest.BadLiveFilter do
                     use Hawk.Resource, model: Hawk.ResourceTest.Course
                   end
                   """)
                 end
  end
end
