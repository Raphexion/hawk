defmodule Hawk.Plans.SpecTest do
  use ExUnit.Case, async: true

  alias Hawk.Plans.Spec

  describe "spec/2" do
    test "renders read, create, update, delete, and action ops for a full resource" do
      spec = Spec.spec([Videdal.Courses])

      courses = spec.resources["courses"]

      assert courses.type == "courses"
      assert courses.resource == Videdal.Courses

      # Find ops by kind. :action appears multiple times, so filter instead of keying.
      read = Enum.find(courses.ops, &(&1.op == :read))
      create = Enum.find(courses.ops, &(&1.op == :create))
      update = Enum.find(courses.ops, &(&1.op == :update))
      delete = Enum.find(courses.ops, &(&1.op == :delete))

      # :read lists the reader's filters and sorts so the AI can find records.
      # Courses declares filters (including custom handlers like :school_name) and sorts.
      assert MapSet.new(read.filters) == MapSet.new([:id, :school_id, :teacher_id, :title, :school_name, :teacher_name])
      assert MapSet.new(read.sorts) == MapSet.new([:id, :title])

      # :create lists creatable attrs and relationships by external name, with source + doc
      assert create.attrs == %{title: %{source: :title, doc: "Human-readable course title."}}
      assert create.relationships == %{
               school: %{source: :school, doc: "The school offering the course.", target: "schools"},
               teacher: %{source: :teacher, doc: "The teacher responsible for the course.", target: "teachers"}
             }

      # :update lists updatable attrs and relationships
      assert update.attrs == %{title: %{source: :title, doc: "Human-readable course title."}}
      assert update.relationships == %{
               school: %{source: :school, doc: "The school offering the course.", target: "schools"},
               teacher: %{source: :teacher, doc: "The teacher responsible for the course.", target: "teachers"}
             }

      # :delete is available (no attrs — the id is provided at authoring time)
      assert delete == %{op: :delete}

      # :action ops — one per declared action, with name, doc, and params (meta unwrapped)
      actions = Enum.filter(courses.ops, &(&1.op == :action))
      open = Enum.find(actions, &(&1.name == "open-registration"))
      close = Enum.find(actions, &(&1.name == "close-registration"))

      assert open.doc == "Open course registration and configure seats and waitlist capacity."
      assert open.params == %{
               seat_count: %{type: :integer, doc: "Seats offered immediately when registration opens.", example: 2},
               waitlist_count: %{type: :integer, doc: "How many waitlist places should be tracked for this course.", example: 1}
             }

      assert close.doc == "Close registration and finalize each student as enrolled, waitlisted, or rejected."
      assert close.params == %{}
    end

    test "omits create/update/delete when writer capability is false" do
      # Hawk.Resource always resolves writer by convention (the :writer opt raises),
      # so no real fixture has writer: false. Test the capability filtering directly
      # by calling resource_ops with a mock resource map.
      mock = %{
        resource: Videdal.Courses,
        json_api: Hawk.JsonApi.Schema.metadata(Videdal.Courses),
        capabilities: %{reader: true, writer: false, json_api: true, live_view: false, actions: false},
        identity: :id
      }

      result = Spec.resource_ops(mock)
      kinds = Enum.map(result.ops, & &1.op)

      assert :read in kinds
      refute :create in kinds
      refute :update in kinds
      refute :delete in kinds
      refute :action in kinds
    end

    test "omits action ops when actions are disabled" do
      # CourseCatalog has writer enabled but no actions module
      spec = Spec.spec([Videdal.CourseCatalog])

      catalog = spec.resources["course-catalog"]
      kinds = Enum.map(catalog.ops, & &1.op)

      assert :read in kinds
      assert :create in kinds
      assert :update in kinds
      assert :delete in kinds
      refute :action in kinds
    end

    test "omits resources with json_api disabled entirely" do
      spec = Spec.spec([Videdal.Courses, Videdal.InternalNotes])

      assert Map.has_key?(spec.resources, "courses")
      refute Map.has_key?(spec.resources, "internal-notes")
    end

    test "includes all declared reader filters (custom handlers included)" do
      spec = Spec.spec([Videdal.Teachers])

      teachers = spec.resources["teachers"]
      read = Enum.find(teachers.ops, &(&1.op == :read))

      # Teachers reader declares filter(:id), filter(:school_id), and custom handlers.
      assert MapSet.new(read.filters) == MapSet.new([:id, :school_id, :teacher_id, :school_name])
      assert read.sorts == [:id]
    end

    test "includes identity as a filter and sort by default" do
      spec = Spec.spec([Videdal.CourseRosters])

      rosters = spec.resources["course-rosters"]
      read = Enum.find(rosters.ops, &(&1.op == :read))

      # CourseRosters declares identity: :course_id
      assert :course_id in read.filters
      assert :course_id in read.sorts
    end
  end
end
