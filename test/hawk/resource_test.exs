defmodule Hawk.ResourceTest.Course do
  use Hawk.Model

  model "hawk_resource_test_courses" do
    field(:title, :string)
  end
end

defmodule Hawk.ResourceTest.Courses.Reader do
  def one(opts), do: {:one, opts}
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
  def all(opts), do: {:all, opts}
end

defmodule Hawk.ResourceTest.CourseSummaries.Policy do
  def read_filter(_authority), do: :all
end

defmodule Hawk.ResourceTest.CourseSummaries.Writer do
  @moduledoc false

  def create(attrs, _authority), do: {:ok, struct!(Hawk.ResourceTest.Course, attrs)}
  def update(model, attrs, _authority), do: {:ok, Map.merge(model, attrs)}
  def delete(_model, _authority), do: :ok
end

defmodule Hawk.ResourceTest.CourseSummaries do
  use Hawk.Resource,
    model: Hawk.ResourceTest.Course,
    json_api: false,
    live_view: false
end

defmodule Hawk.ResourceTest.CustomFacade.CustomReader do
  def one(opts), do: {:custom_one, opts}
  def all(opts), do: {:custom_all, opts}
end

defmodule Hawk.ResourceTest.CustomFacade.Policy do
  def read_filter(_authority), do: :none
end

defmodule Hawk.ResourceTest.CustomFacade.CustomJsonApi do
  def __hawk_json_api__, do: %{type: "custom-courses"}
end

defmodule Hawk.ResourceTest.CustomFacade.CustomLiveView do
  def __hawk_live_view__, do: %{index: %{}, show: %{}}
end

defmodule Hawk.ResourceTest.CustomFacade.Writer do
  @moduledoc false

  def create(attrs, _authority), do: {:ok, struct!(Hawk.ResourceTest.Course, attrs)}
  def update(model, attrs, _authority), do: {:ok, Map.merge(model, attrs)}
  def delete(_model, _authority), do: :ok
end

defmodule Hawk.ResourceTest.CustomFacade do
  use Hawk.Resource,
    model: Hawk.ResourceTest.Course,
    reader: Hawk.ResourceTest.CustomFacade.CustomReader,
    json_api: Hawk.ResourceTest.CustomFacade.CustomJsonApi,
    live_view: Hawk.ResourceTest.CustomFacade.CustomLiveView
end

defmodule Hawk.ResourceTest do
  use ExUnit.Case, async: true

  alias Hawk.ResourceTest.{Course, Courses, CourseSummaries, CustomFacade}

  test "convention resource facade delegates reader, writer, and action dispatch" do
    authority = Hawk.Authority.system()
    course = %Course{id: Videdal.course_id(), title: "Math"}

    assert Courses.one(authority: authority) == {:one, [authority: authority]}
    assert Courses.all(authority: authority) == {:all, [authority: authority]}
    assert Courses.create(%{title: "Math"}, authority) == {:create, %{title: "Math"}, authority}

    assert Courses.update(course, %{title: "Science"}, authority) ==
             {:update, course, %{title: "Science"}, authority}

    assert Courses.delete(course, authority) == {:delete, course, authority}

    refute function_exported?(Courses, :open_registration, 3)

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
             json_api: true,
             live_view: true,
             actions: true
           }
  end

  test "writer is always resolved by convention and delegates are generated" do
    assert CourseSummaries.one(authority: Hawk.Authority.system()) ==
             {:one, [authority: Hawk.Authority.system()]}

    assert CourseSummaries.__hawk_resource__(:writer) == Hawk.ResourceTest.CourseSummaries.Writer
    assert CourseSummaries.__hawk_resource__(:json_api) == false
    assert CourseSummaries.__hawk_resource__(:live_view) == false
    assert function_exported?(CourseSummaries, :create, 2)
    assert function_exported?(CourseSummaries, :update, 3)
    assert function_exported?(CourseSummaries, :delete, 2)
  end

  test "explicit modules override conventions" do
    assert CustomFacade.all(authority: Hawk.Authority.system()) ==
             {:custom_all, [authority: Hawk.Authority.system()]}

    assert CustomFacade.__hawk_resource__(:reader) == Hawk.ResourceTest.CustomFacade.CustomReader
    assert CustomFacade.__hawk_resource__(:policy) == Hawk.ResourceTest.CustomFacade.Policy

    assert CustomFacade.__hawk_resource__(:json_api) ==
             Hawk.ResourceTest.CustomFacade.CustomJsonApi

    assert CustomFacade.__hawk_resource__(:live_view) ==
             Hawk.ResourceTest.CustomFacade.CustomLiveView
  end

  test "missing conventional modules warn at compile time instead of raising" do
    warning =
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        Code.compile_string("""
        defmodule Hawk.ResourceTest.Broken.Writer do
          def create(attrs, _authority), do: {:ok, struct!(Hawk.ResourceTest.Course, attrs)}
          def update(model, attrs, _authority), do: {:ok, Map.merge(model, attrs)}
          def delete(_model, _authority), do: :ok
        end

        defmodule Hawk.ResourceTest.Broken do
          use Hawk.Resource,
            model: Hawk.ResourceTest.Course,
            json_api: false,
            live_view: false
        end
        """)
      end)

    assert warning =~ "Hawk resource reader module Hawk.ResourceTest.Broken.Reader is not available yet"
    assert warning =~ "Run `mix hawk.validate` to enforce"
    assert function_exported?(Hawk.ResourceTest.Broken, :__hawk_resource__, 1)
  end

  test "strict validation raises on missing siblings (the mix hawk.validate gate)" do
    modules = %{
      model: Hawk.ResourceTest.Course,
      reader: Hawk.ResourceTest.StrictMissing.Reader,
      policy: Hawk.ResourceTest.Courses.Policy,
      writer: Hawk.ResourceTest.Courses.Writer,
      json_api: false,
      live_view: false,
      actions: false
    }

    assert_raise ArgumentError,
                 ~r/Hawk resource reader module Hawk.ResourceTest.StrictMissing.Reader is not available/,
                 fn -> Hawk.Resource.Validation.validate!(modules, :strict) end
  end

  test "mix hawk.validate passes for complete resources and fails strictly for missing siblings" do
    ExUnit.CaptureIO.capture_io(fn ->
      assert Mix.Tasks.Hawk.Validate.run(["Hawk.ResourceTest.Courses"]) == :ok
    end)

    ensure_broken_resource_compiled!()

    stderr =
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        assert_raise Mix.Error, ~r/Hawk validation failed/, fn ->
          Mix.Tasks.Hawk.Validate.run(["Hawk.ResourceTest.Broken"])
        end
      end)

    assert stderr =~ "reader module Hawk.ResourceTest.Broken.Reader is not available"
  end

  test "mix hawk.validate discovers all compiled Hawk resources" do
    output =
      ExUnit.CaptureIO.capture_io(fn ->
        assert Mix.Tasks.Hawk.Validate.run([]) == :ok
      end)

    assert output =~ "Hawk validation passed"
  end

  defp ensure_broken_resource_compiled! do
    unless Code.ensure_loaded?(Hawk.ResourceTest.Broken) do
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        Code.compile_string("""
        defmodule Hawk.ResourceTest.Broken.Writer do
          def create(attrs, _authority), do: {:ok, struct!(Hawk.ResourceTest.Course, attrs)}
          def update(model, attrs, _authority), do: {:ok, Map.merge(model, attrs)}
          def delete(_model, _authority), do: :ok
        end

        defmodule Hawk.ResourceTest.Broken do
          use Hawk.Resource,
            model: Hawk.ResourceTest.Course,
            json_api: false,
            live_view: false
        end
        """)
      end)
    end
  end

  test "malformed adapter modules fail at compile time" do
    assert_raise ArgumentError,
                 ~r/Hawk resource json_api module Hawk.ResourceTest.Malformed.JsonApi must define __hawk_json_api__\/0/,
                 fn ->
                   Code.compile_string("""
                   defmodule Hawk.ResourceTest.Malformed.Reader do
                     def one(opts), do: {:one, opts}
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

  test "json_api writable relationships must be belongs_to associations" do
    assert_raise ArgumentError,
                 ~r/Hawk resource json_api module Hawk.ResourceTest.BadWritableRelationship.JsonApi relationship :grades is writable but references a :many association on Videdal.Course; only belongs_to relationships can be mapped to writer attrs/,
                 fn ->
                   Code.compile_string("""
                   defmodule Hawk.ResourceTest.BadWritableRelationship.Reader do
                     def one(opts), do: {:one, opts}
                     def all(opts), do: {:all, opts}
                   end

                   defmodule Hawk.ResourceTest.BadWritableRelationship.Policy do
                     def read_filter(_authority), do: :all
                   end

                   defmodule Hawk.ResourceTest.BadWritableRelationship.Writer do
                     def create(attrs, authority), do: {:create, attrs, authority}
                     def update(model, attrs, authority), do: {:update, model, attrs, authority}
                     def delete(model, authority), do: {:delete, model, authority}
                   end

                   defmodule Hawk.ResourceTest.BadWritableRelationship.JsonApi do
                     use Hawk.JsonApi.Resource

                     type("courses")
                     relationship(:grades, writable: true)
                   end

                   defmodule Hawk.ResourceTest.BadWritableRelationship.LiveView do
                     def __hawk_live_view__, do: %{}
                   end

                   defmodule Hawk.ResourceTest.BadWritableRelationship do
                     use Hawk.Resource,
                       model: Videdal.Course,
                       reader: Hawk.ResourceTest.BadWritableRelationship.Reader,
                       json_api: Hawk.ResourceTest.BadWritableRelationship.JsonApi,
                       live_view: Hawk.ResourceTest.BadWritableRelationship.LiveView
                   end
                   """)
                 end
  end

  test "belongs_to relationships whose related key diverges from the related identity fail at compile time" do
    # The FK value is rendered as the relationship id, so the related resource's
    # identity must equal the association's related_key. Here the related model
    # declares identity: :course_id but the belongs_to uses the default related_key :id,
    # so the FK cannot render the related identity.
    assert_raise ArgumentError,
                 ~r/relationship :roster .* is a belongs_to whose related key :id does not match the related resource .* identity :course_id/,
                 fn ->
                   Code.compile_string("""
                   defmodule Hawk.ResourceTest.DivergentIdentity.Roster do
                     use Ecto.Schema
                     @primary_key {:course_id, :binary_id, autogenerate: true}
                     @foreign_key_type :binary_id
                     schema "divergent_rosters" do
                       field(:title, :string)
                     end
                   end

                   defmodule Hawk.ResourceTest.DivergentIdentity.Rosters.JsonApi do
                     use Hawk.JsonApi.Resource
                     type("divergent-rosters")
                     attribute(:title, writable: true)
                   end

                   defmodule Hawk.ResourceTest.DivergentIdentity.Rosters.Policy do
                     use Hawk.Policy
                     read do
                       role(:system, :all)
                     end
                     write(roles: [:system])
                   end

                   defmodule Hawk.ResourceTest.DivergentIdentity.Rosters.Reader do
                     use Hawk.Reader.Resource,
                       repo: Videdal.Repo,
                       schema: Hawk.ResourceTest.DivergentIdentity.Roster
                     filter(:course_id)
                   end

                   defmodule Hawk.ResourceTest.DivergentIdentity.Rosters.Writer do
                     use Hawk.Writer.Resource,
                       model: Hawk.ResourceTest.DivergentIdentity.Roster,
                       repo: Videdal.Repo,
                       policy: Hawk.ResourceTest.DivergentIdentity.Rosters.Policy
                     create do
                       cast([:title])
                     end
                     update do
                       cast([:title])
                     end
                     delete(:default)
                   end

                   defmodule Hawk.ResourceTest.DivergentIdentity.Rosters do
                     use Hawk.Resource,
                       model: Hawk.ResourceTest.DivergentIdentity.Roster,
                       identity: :course_id,
                       live_view: false
                   end

                   defmodule Hawk.ResourceTest.DivergentIdentity.Model do
                     use Ecto.Schema
                     @primary_key {:id, :binary_id, autogenerate: true}
                     @foreign_key_type :binary_id
                     schema "divergent_models" do
                       field(:name, :string)
                       belongs_to(:roster, Hawk.ResourceTest.DivergentIdentity.Roster)
                     end
                   end

                   defmodule Hawk.ResourceTest.DivergentIdentity.Models.JsonApi do
                     use Hawk.JsonApi.Resource
                     type("divergent-models")
                     attribute(:name, writable: true)
                     relationship(:roster, writable: true)
                   end

                   defmodule Hawk.ResourceTest.DivergentIdentity.Models.Policy do
                     use Hawk.Policy
                     read do
                       role(:system, :all)
                     end
                     write(roles: [:system])
                   end

                   defmodule Hawk.ResourceTest.DivergentIdentity.Models.Reader do
                     use Hawk.Reader.Resource,
                       repo: Videdal.Repo,
                       schema: Hawk.ResourceTest.DivergentIdentity.Model
                     filter(:id)
                   end

                   defmodule Hawk.ResourceTest.DivergentIdentity.Models.Writer do
                     use Hawk.Writer.Resource,
                       model: Hawk.ResourceTest.DivergentIdentity.Model,
                       repo: Videdal.Repo,
                       policy: Hawk.ResourceTest.DivergentIdentity.Models.Policy
                     create do
                       cast([:name])
                     end
                     update do
                       cast([:name])
                     end
                     delete(:default)
                   end

                   defmodule Hawk.ResourceTest.DivergentIdentity.Models do
                     use Hawk.Resource,
                       model: Hawk.ResourceTest.DivergentIdentity.Model,
                       live_view: false
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

  test "live_view form fields must reference model fields" do
    assert_raise ArgumentError,
                 ~r/Hawk resource live_view module Hawk.ResourceTest.BadLiveFormField.LiveView create_form field :headline source :missing_title must reference a field on Hawk.ResourceTest.Course/,
                 fn ->
                   Code.compile_string("""
                   defmodule Hawk.ResourceTest.BadLiveFormField.Reader do
                     def one(opts), do: {:one, opts}
                     def all(opts), do: {:all, opts}
                   end

                   defmodule Hawk.ResourceTest.BadLiveFormField.Policy do
                     def read_filter(_authority), do: :all
                   end

                   defmodule Hawk.ResourceTest.BadLiveFormField.Writer do
                     def create(attrs, authority), do: {:create, attrs, authority}
                     def update(model, attrs, authority), do: {:update, model, attrs, authority}
                     def delete(model, authority), do: {:delete, model, authority}
                   end

                   defmodule Hawk.ResourceTest.BadLiveFormField.JsonApi do
                     def __hawk_json_api__, do: %{type: "courses"}
                   end

                   defmodule Hawk.ResourceTest.BadLiveFormField.LiveView do
                     use Hawk.LiveView.Resource

                     create_form do
                       field(:headline, source: :missing_title)
                     end
                   end

                   defmodule Hawk.ResourceTest.BadLiveFormField do
                     use Hawk.Resource, model: Hawk.ResourceTest.Course
                   end
                   """)
                 end
  end

  test "writer form helpers must be declared as a pair" do
    assert_raise ArgumentError,
                 ~r"Hawk resource writer module Hawk.ResourceTest.PartialFormWriter.Writer must define change_update/3 when change_create/2 is defined",
                 fn ->
                   Code.compile_string("""
                   defmodule Hawk.ResourceTest.PartialFormWriter.Reader do
                     def one(opts), do: {:one, opts}
                     def all(opts), do: {:all, opts}
                   end

                   defmodule Hawk.ResourceTest.PartialFormWriter.Policy do
                     def read_filter(_authority), do: :all
                   end

                   defmodule Hawk.ResourceTest.PartialFormWriter.Writer do
                     def create(attrs, authority), do: {:create, attrs, authority}
                     def update(model, attrs, authority), do: {:update, model, attrs, authority}
                     def delete(model, authority), do: {:delete, model, authority}
                     def change_create(attrs, authority), do: {:change_create, attrs, authority}
                   end

                   defmodule Hawk.ResourceTest.PartialFormWriter.JsonApi do
                     def __hawk_json_api__, do: %{type: "courses"}
                   end

                   defmodule Hawk.ResourceTest.PartialFormWriter.LiveView do
                     def __hawk_live_view__, do: %{}
                   end

                   defmodule Hawk.ResourceTest.PartialFormWriter do
                     use Hawk.Resource, model: Hawk.ResourceTest.Course
                   end
                   """)
                 end
  end

  test "live_view searches must be declared reader filters" do
    assert_raise ArgumentError,
                 ~r/Hawk resource live_view module Hawk.ResourceTest.BadLiveSearch.LiveView index filter :title must be declared by reader Hawk.ResourceTest.BadLiveSearch.Reader/,
                 fn ->
                   Code.compile_string("""
                   defmodule Hawk.ResourceTest.BadLiveSearch.Reader do
                     def one(opts), do: {:one, opts}
                     def all(opts), do: {:all, opts}
                     def filter_keys, do: MapSet.new([:teacher_id])
                   end

                   defmodule Hawk.ResourceTest.BadLiveSearch.Policy do
                     def read_filter(_authority), do: :all
                   end

                   defmodule Hawk.ResourceTest.BadLiveSearch.Writer do
                     def create(attrs, authority), do: {:create, attrs, authority}
                     def update(model, attrs, authority), do: {:update, model, attrs, authority}
                     def delete(model, authority), do: {:delete, model, authority}
                   end

                   defmodule Hawk.ResourceTest.BadLiveSearch.JsonApi do
                     def __hawk_json_api__, do: %{type: "courses"}
                   end

                   defmodule Hawk.ResourceTest.BadLiveSearch.LiveView do
                     use Hawk.LiveView.Resource

                     index do
                       search(:title, operator: :ilike)
                     end
                   end

                   defmodule Hawk.ResourceTest.BadLiveSearch do
                     use Hawk.Resource, model: Hawk.ResourceTest.Course
                   end
                   """)
                 end
  end

  test "live_view sorts must be declared reader sorts" do
    assert_raise ArgumentError,
                 ~r/Hawk resource live_view module Hawk.ResourceTest.BadLiveSort.LiveView index sort :title must be declared by reader Hawk.ResourceTest.BadLiveSort.Reader/,
                 fn ->
                   Code.compile_string("""
                   defmodule Hawk.ResourceTest.BadLiveSort.Reader do
                     def one(opts), do: {:one, opts}
                     def all(opts), do: {:all, opts}
                     def sort_keys, do: MapSet.new([:id])
                   end

                   defmodule Hawk.ResourceTest.BadLiveSort.Policy do
                     def read_filter(_authority), do: :all
                   end

                   defmodule Hawk.ResourceTest.BadLiveSort.Writer do
                     def create(attrs, authority), do: {:create, attrs, authority}
                     def update(model, attrs, authority), do: {:update, model, attrs, authority}
                     def delete(model, authority), do: {:delete, model, authority}
                   end

                   defmodule Hawk.ResourceTest.BadLiveSort.JsonApi do
                     def __hawk_json_api__, do: %{type: "courses"}
                   end

                   defmodule Hawk.ResourceTest.BadLiveSort.LiveView do
                     use Hawk.LiveView.Resource

                     index do
                       sort(:title)
                     end
                   end

                   defmodule Hawk.ResourceTest.BadLiveSort do
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
