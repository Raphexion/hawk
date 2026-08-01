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

defmodule Hawk.LiveViewTest.CourseManualEventsLive do
  @moduledoc false

  use Hawk.LiveView,
    resource: Videdal.Courses,
    as: :course,
    events: false
end

defmodule Hawk.LiveViewTest.Labels do
  @moduledoc false

  def field_label({:gettext, msgid}), do: "translated:#{msgid}"
  def field_label({:dgettext, domain, msgid}), do: "translated:#{domain}:#{msgid}"
end

defmodule Hawk.LiveViewTest.CourseTranslatedLive do
  @moduledoc false

  use Hawk.LiveView,
    resource: Videdal.Courses,
    as: :course,
    label_resolver: Hawk.LiveViewTest.Labels
end

defmodule Hawk.LiveViewTest do
  use Videdal.DatabaseCase, async: true

  import Hawk.TestSocket, only: [socket: 0]

  alias Hawk.Authority

  alias Hawk.LiveViewTest.{
    CourseIndexLive,
    CourseManualEventsLive,
    CourseShowLive,
    CourseTranslatedLive
  }

  alias Videdal.{Course, Repo}

  @course_id Videdal.course_id()
  @other_course_id Videdal.other_course_id()
  @school_id Videdal.school_id()
  @student_id Videdal.student_id()
  @teacher_id Videdal.teacher_id()

  test "assign_index loads resources into predictable plural assigns" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)
    math = insert(:course, school_id: school.id, teacher_id: teacher.id, title: "Math")
    insert(:course, school_id: school.id, teacher_id: teacher.id, title: "Zebra")
    authority = school_admin(school)

    socket =
      CourseIndexLive.assign_index(socket(), authority, sort: [{:asc, :title}], page: %{size: 10})

    assert [first, second] = socket.assigns.courses
    assert first.id == math.id
    assert first.title == "Math"
    assert second.title == "Zebra"
    # Path-source columns declare the preloads; the helper derives them and
    # loads the associations without a caller-supplied :preloads opt.
    assert %Videdal.Teacher{} = first.teacher
    assert %Videdal.School{} = first.school
    assert first.teacher.id == teacher.id
    assert first.school.id == school.id
    assert socket.assigns.hawk_resource == :course
    assert socket.assigns.hawk_page == %{size: 10}

    assert socket.assigns.hawk_table == [
             %{name: :title, label: "Course"},
             %{name: :teacher_name, label: "Teacher", source: [:teacher, :name]},
             %{name: :school_name, label: "School", source: [:school, :name]},
             %{name: :registration_state, label: "Registration"},
             %{name: :seat_count, label: "Seats"},
             %{name: :waitlist_count, label: "Waitlist"}
           ]
  end

  test "assign_index raises a helpful error when policy-aware preloads filter a required source path" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)
    insert(:course, school_id: school.id, teacher_id: teacher.id, title: "Math")

    authority = Authority.new(:parent, Videdal.parent_id(), scopes: %{school_id: school.id})

    assert_raise ArgumentError,
                 ~r/Hawk\.LiveView could not resolve index field :teacher_name .*filtered the association for role :parent/,
                 fn -> CourseIndexLive.assign_index(socket(), authority) end
  end

  test "assign_index applies declared LiveView filters as reader narrowing" do
    school = insert(:school)
    teacher1 = insert(:teacher, school_id: school.id)
    teacher2 = insert(:teacher, school_id: school.id)
    course1 = insert(:course, school_id: school.id, teacher_id: teacher1.id, title: "Math")
    insert(:course, school_id: school.id, teacher_id: teacher2.id, title: "Other")
    authority = school_admin(school)

    socket =
      CourseIndexLive.assign_index(socket(), authority, params: %{"filter" => %{"teacher_id" => teacher1.id}})

    assert [course] = socket.assigns.courses
    assert course.id == course1.id
  end

  test "assign_index applies search, sort, and page params" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)
    history = insert(:course, school_id: school.id, teacher_id: teacher.id, title: "History")
    insert(:course, school_id: school.id, teacher_id: teacher.id, title: "Math")
    authority = school_admin(school)

    socket =
      CourseIndexLive.assign_index(socket(), authority,
        params: %{
          "search" => %{"title" => "histo"},
          "sort" => "-title",
          "page" => %{"number" => "1", "size" => "10"}
        }
      )

    assert [course] = socket.assigns.courses
    assert course.id == history.id
    assert socket.assigns.hawk_page == %{number: 1, size: 10}
    assert socket.assigns.hawk_index_state.sort == [{:desc, :title}]
    assert socket.assigns.hawk_index_state.filter == %{title: {:ilike, "%histo%"}}
  end

  test "assign_index combines LiveView params with existing caller filters" do
    school = insert(:school)
    teacher1 = insert(:teacher, school_id: school.id)
    teacher2 = insert(:teacher, school_id: school.id)
    course1 = insert(:course, school_id: school.id, teacher_id: teacher1.id, title: "Math")
    insert(:course, school_id: school.id, teacher_id: teacher2.id, title: "Other")
    other_school = insert(:school)

    insert(:course,
      school_id: other_school.id,
      teacher_id: insert(:teacher, school_id: other_school.id).id,
      title: "Math"
    )

    socket =
      CourseIndexLive.assign_index(socket(), Authority.system(),
        filter: %{school_id: school.id},
        params: %{"filter" => %{"teacher_id" => teacher1.id}}
      )

    assert [course] = socket.assigns.courses
    assert course.id == course1.id
  end

  test "assign_index rejects undeclared LiveView filters without creating atoms" do
    hostile = "hawk_hostile_live_filter_#{System.unique_integer([:positive])}"

    assert_raise ArgumentError, "unknown LiveView filter #{inspect(hostile)}", fn ->
      CourseIndexLive.assign_index(socket(), Authority.system(), params: %{"filter" => %{hostile => "boom"}})
    end

    refute_existing_atom(hostile)
  end

  test "assign_show loads one resource into predictable singular assigns" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)
    course = insert(:course, school_id: school.id, teacher_id: teacher.id, title: "Math")
    authority = school_admin(school)

    socket = CourseShowLive.assign_show(socket(), authority, course.id)

    assert socket.assigns.course.id == course.id
    assert socket.assigns.course.title == "Math"
    assert socket.assigns.hawk_resource == :course

    assert socket.assigns.hawk_fields == [
             %{name: :title},
             %{name: :teacher_name, label: "Teacher", source: [:teacher, :name]},
             %{name: :registration_state, label: "Registration"},
             %{name: :seat_count, label: "Seats"},
             %{name: :waitlist_count, label: "Waitlist"}
           ]
  end

  test "assign_show stores a LiveView-friendly error when the record is missing" do
    Process.put({Videdal.Repo, :all_results}, [])

    socket = CourseShowLive.assign_show(socket(), Authority.system(), @other_course_id)

    assert socket.assigns.hawk_error == %{base: ["course was not found"]}
  end

  test "assign_show can load by a declared natural key" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)
    course = insert(:course, school_id: school.id, teacher_id: teacher.id, title: "Math")
    authority = school_admin(school)

    socket = CourseShowLive.assign_show(socket(), authority, "Math", lookup: :title)

    assert socket.assigns.course.id == course.id
  end

  test "assign_show merges an existing filter when loading one resource" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)
    course = insert(:course, school_id: school.id, teacher_id: teacher.id, title: "Math")
    authority = school_admin(school)

    socket =
      CourseShowLive.assign_show(socket(), authority, course.id, filter: %{school_id: school.id})

    assert socket.assigns.course.id == course.id
  end

  test "assign_index exposes lightweight page metadata for admin tables" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)
    insert(:course, school_id: school.id, teacher_id: teacher.id, title: "Math")
    insert(:course, school_id: school.id, teacher_id: teacher.id, title: "Zebra")
    authority = school_admin(school)

    socket =
      CourseIndexLive.assign_index(socket(), authority, sort: [{:asc, :title}], page: %{size: 1})

    assert socket.assigns.hawk_index_meta == %{
             count: 1,
             has_more?: true,
             page: %{size: 1},
             resource: :course,
             plural_resource: :courses
           }
  end

  test "generated hawk_field_value resolves show field sources and formatters" do
    course = %Course{id: @course_id, title: "Math"}

    assert CourseIndexLive.hawk_field_value(course, %{name: :title}) == "Math"
    assert CourseIndexLive.hawk_field_value(course, %{name: :display_title, source: :title}) == "Math"
    assert CourseIndexLive.hawk_field_value(course, %{name: :title, format: &String.upcase/1}) == "MATH"
  end

  test "assign_read_form assigns display-only form state for read-only admin surfaces" do
    course = %Course{id: @course_id, title: "Math"}

    socket = CourseIndexLive.assign_read_form(socket(), course)

    assert %Phoenix.HTML.Form{} = socket.assigns.course_form
    assert socket.assigns.course_form.source["title"] == course.title
    assert socket.assigns.course_form_fields == [%{name: :title, label: "Course"}]
    assert socket.assigns.hawk_form_states.course.mode == :read
  end

  test "assign_new_form assigns a keyed validation form and create fields without persisting" do
    socket = CourseIndexLive.assign_new_form(socket(), Authority.system())

    assert %Phoenix.HTML.Form{action: :validate, source: %Ecto.Changeset{valid?: false}} = socket.assigns.course_form
    assert errors_on(socket.assigns.course_form).title == ["can't be blank"]

    assert socket.assigns.course_form_fields == [
             %{name: :title, label: "Course"},
             %{name: :school_id, label: "School"},
             %{name: :teacher_id, label: "Teacher"}
           ]

    assert socket.assigns.hawk_form_states.course.mode == :create
    refute_received {:videdal_repo, :insert, _changeset}
  end

  test "generated hawk_field_label resolves labels through an optional app resolver" do
    assert CourseTranslatedLive.hawk_field_label(%{name: :title, label: {:gettext, "Course"}}) ==
             "translated:Course"

    assert CourseTranslatedLive.hawk_field_label(%{
             name: :teacher_id,
             label: {:dgettext, "courses", "Teacher"}
           }) ==
             "translated:courses:Teacher"

    assert CourseTranslatedLive.hawk_field_label(%{name: :registration_state}) ==
             "Registration state"

    assert CourseIndexLive.hawk_field_label(%{name: :title, label: {:gettext, "Course"}}) ==
             "Course"
  end

  test "assign_new_form applies forced attrs to validation without rendering them" do
    socket =
      CourseIndexLive.assign_new_form(socket(), Authority.system(),
        forced_attrs: %{school_id: @school_id, teacher_id: @teacher_id},
        hidden: [:school_id, :teacher_id]
      )

    assert %Phoenix.HTML.Form{action: :validate, source: %Ecto.Changeset{valid?: false}} = socket.assigns.course_form
    assert errors_on(socket.assigns.course_form).title == ["can't be blank"]
    refute Map.has_key?(errors_on(socket.assigns.course_form), :school_id)
    refute Map.has_key?(errors_on(socket.assigns.course_form), :teacher_id)
    assert socket.assigns.course_form_fields == [%{name: :title, label: "Course"}]

    assert socket.assigns.hawk_form_states.course.forced_attrs == %{
             school_id: @school_id,
             teacher_id: @teacher_id
           }
  end

  test "assign_edit_form assigns a keyed validation form and update fields for an existing model" do
    course = %Course{
      id: @course_id,
      title: "Math",
      school_id: @school_id,
      teacher_id: @teacher_id
    }

    socket = CourseIndexLive.assign_edit_form(socket(), course, Authority.system())

    assert %Phoenix.HTML.Form{action: :validate, source: %Ecto.Changeset{valid?: true}} = socket.assigns.course_form
    assert socket.assigns.course_form.data == course
    assert socket.assigns.course_form_fields == [%{name: :title, label: "Course"}]
    assert socket.assigns.hawk_form_states.course.mode == :update
    assert socket.assigns.hawk_form_states.course.model == course
    refute_received {:videdal_repo, :update, _changeset}
  end

  test "generated hawk_validate helper updates the create form with live errors" do
    socket = CourseIndexLive.assign_new_form(socket(), Authority.system())

    {:noreply, socket} = CourseIndexLive.hawk_validate(%{"course" => %{"title" => ""}}, socket)

    assert %Phoenix.HTML.Form{action: :validate, source: %Ecto.Changeset{valid?: false}} = socket.assigns.course_form
    assert errors_on(socket.assigns.course_form).title == ["can't be blank"]
    refute_received {:videdal_repo, :insert, _changeset}
  end

  test "validate event updates the create form with live errors" do
    socket = CourseIndexLive.assign_new_form(socket(), Authority.system())

    {:noreply, socket} =
      CourseIndexLive.handle_event("hawk:validate", %{"course" => %{"title" => ""}}, socket)

    assert %Phoenix.HTML.Form{action: :validate, source: %Ecto.Changeset{valid?: false}} = socket.assigns.course_form
    assert errors_on(socket.assigns.course_form).title == ["can't be blank"]
    refute_received {:videdal_repo, :insert, _changeset}
  end

  test "validate event updates the edit form with live custom validation errors" do
    course = %Course{
      id: @course_id,
      title: "Math",
      school_id: @school_id,
      teacher_id: @teacher_id
    }

    socket = CourseIndexLive.assign_edit_form(socket(), course, Authority.system())

    {:noreply, socket} =
      CourseIndexLive.handle_event(
        "hawk:validate",
        %{"course" => %{"title" => "Forbidden"}},
        socket
      )

    assert %Phoenix.HTML.Form{action: :validate, source: %Ecto.Changeset{valid?: false}} = socket.assigns.course_form
    assert errors_on(socket.assigns.course_form).title == ["is reserved"]
    refute_received {:videdal_repo, :update, _changeset}
  end

  test "generated hawk_save helper supports custom success behavior" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)
    socket = CourseIndexLive.assign_new_form(socket(), Authority.system())

    {:noreply, socket} =
      CourseIndexLive.hawk_save(
        %{
          "course" => %{
            "title" => "History",
            "school_id" => school.id,
            "teacher_id" => teacher.id
          }
        },
        socket,
        on_success: fn socket, course ->
          socket
          |> Map.put(:patched_to, "/courses/#{course.title}")
        end
      )

    assert socket.patched_to == "/courses/History"
    assert %Course{title: "History"} = socket.assigns.course
  end

  test "events false still generates helpers but not default form or delete handlers" do
    socket = CourseManualEventsLive.assign_new_form(socket(), Authority.system())

    {:noreply, socket} =
      CourseManualEventsLive.hawk_validate(%{"course" => %{"title" => ""}}, socket)

    assert errors_on(socket.assigns.course_form).title == ["can't be blank"]
    refute function_exported?(CourseManualEventsLive, :handle_event, 3)
  end

  test "save event merges forced attrs after client params when creating" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)

    socket =
      CourseIndexLive.assign_new_form(socket(), Authority.system(),
        forced_attrs: %{school_id: school.id, teacher_id: teacher.id}
      )

    {:noreply, socket} =
      CourseIndexLive.handle_event(
        "hawk:save",
        %{
          "course" => %{
            "title" => "History",
            "school_id" => @other_course_id,
            "teacher_id" => @other_course_id
          }
        },
        socket
      )

    assert %Course{title: "History"} = socket.assigns.course
    assert socket.assigns.course.school_id == school.id
    assert socket.assigns.course.teacher_id == teacher.id
    assert Repo.get!(Course, socket.assigns.course.id).school_id == school.id
  end

  test "save event creates, assigns the saved model, and switches form state to edit" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)
    socket = CourseIndexLive.assign_new_form(socket(), Authority.system())

    {:noreply, socket} =
      CourseIndexLive.handle_event(
        "hawk:save",
        %{
          "course" => %{
            "title" => "History",
            "school_id" => school.id,
            "teacher_id" => teacher.id
          }
        },
        socket
      )

    assert %Course{title: "History"} = socket.assigns.course
    assert socket.assigns.course.school_id == school.id
    assert socket.assigns.course.teacher_id == teacher.id

    assert %Phoenix.HTML.Form{action: :validate, source: %Ecto.Changeset{valid?: true}} = socket.assigns.course_form
    assert socket.assigns.hawk_form_states.course.mode == :update
    assert socket.assigns.hawk_form_states.course.model == socket.assigns.course
    assert Repo.get!(Course, socket.assigns.course.id).title == "History"
  end

  test "save event keeps create form with insert errors when create is invalid" do
    socket = CourseIndexLive.assign_new_form(socket(), Authority.system())

    {:noreply, socket} =
      CourseIndexLive.handle_event("hawk:save", %{"course" => %{"title" => ""}}, socket)

    assert %Phoenix.HTML.Form{action: :insert, source: %Ecto.Changeset{valid?: false}} = socket.assigns.course_form
    assert errors_on(socket.assigns.course_form).title == ["can't be blank"]
    assert socket.assigns.hawk_form_states.course.mode == :create
    refute_received {:videdal_repo, :insert, _changeset}
  end

  test "save event updates and assigns the saved model" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)
    course = insert(:course, school_id: school.id, teacher_id: teacher.id, title: "Math")
    course_id = course.id

    socket = CourseIndexLive.assign_edit_form(socket(), course, Authority.system())

    {:noreply, socket} =
      CourseIndexLive.handle_event("hawk:save", %{"course" => %{"title" => "History"}}, socket)

    assert %Course{id: ^course_id, title: "History"} = socket.assigns.course
    assert socket.assigns.hawk_form_states.course.mode == :update
    assert socket.assigns.hawk_form_states.course.model == socket.assigns.course
    assert Repo.get!(Course, course_id).title == "History"
  end

  test "save event keeps edit form with update errors when update is invalid" do
    course = %Course{
      id: @course_id,
      title: "Math",
      school_id: @school_id,
      teacher_id: @teacher_id
    }

    socket = CourseIndexLive.assign_edit_form(socket(), course, Authority.system())

    {:noreply, socket} =
      CourseIndexLive.handle_event("hawk:save", %{"course" => %{"title" => "Forbidden"}}, socket)

    assert %Phoenix.HTML.Form{action: :update, source: %Ecto.Changeset{valid?: false}} = socket.assigns.course_form
    assert errors_on(socket.assigns.course_form).title == ["is reserved"]
    assert socket.assigns.hawk_form_states.course.mode == :update
    refute_received {:videdal_repo, :update, _changeset}
  end

  test "save event stores LiveView-friendly authorization errors" do
    socket =
      CourseIndexLive.assign_new_form(
        socket(),
        Authority.new(:student, @student_id, scopes: %{school_id: @school_id})
      )

    {:noreply, socket} =
      CourseIndexLive.handle_event(
        "hawk:save",
        %{
          "course" => %{
            "title" => "History",
            "school_id" => @school_id,
            "teacher_id" => @teacher_id
          }
        },
        socket
      )

    assert socket.assigns.hawk_error == %{base: ["You are not allowed to create this course."]}
    refute_received {:videdal_repo, :insert, _changeset}
  end

  test "delete event deletes the resource and refreshes the index assign" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)
    course = insert(:course, school_id: school.id, teacher_id: teacher.id, title: "Math")
    course_id = course.id
    authority = school_admin(school)

    {:noreply, socket} =
      CourseIndexLive.handle_event(
        "hawk:delete",
        %{"id" => course_id, "authority" => authority},
        socket()
      )

    refute Enum.any?(socket.assigns.courses, &(&1.id == course_id))
    refute Repo.get(Course, course_id)
  end

  test "delete event stores a LiveView-friendly not found error" do
    Process.put({Videdal.Repo, :all_results}, [])

    {:noreply, socket} =
      CourseIndexLive.handle_event(
        "hawk:delete",
        %{"id" => @other_course_id, "authority" => Authority.system()},
        socket()
      )

    assert socket.assigns.hawk_error == %{base: ["course was not found"]}
  end

  test "delete event stores LiveView-friendly authorization errors" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)
    course = insert(:course, school_id: school.id, teacher_id: teacher.id, title: "Math")
    student = insert(:student, school_id: school.id)
    course_id = course.id

    authority =
      Authority.new(:student, student.id, scopes: %{school_id: school.id, student_id: student.id})

    {:noreply, socket} =
      CourseIndexLive.handle_event(
        "hawk:delete",
        %{"id" => course_id, "authority" => authority},
        socket()
      )

    assert socket.assigns.hawk_error == %{base: ["You are not allowed to delete this course."]}
    assert Repo.get!(Course, course_id)
  end

  defp errors_on(%Phoenix.HTML.Form{source: changeset}), do: errors_on(changeset)

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  defp school_admin(school) do
    Authority.new(:school_admin, Videdal.school_admin_id(), scopes: %{school_id: school.id})
  end

  defp refute_existing_atom(value) do
    _existing = String.to_existing_atom(value)
    flunk("expected #{inspect(value)} not to be an existing atom")
  rescue
    ArgumentError -> :ok
  end
end
