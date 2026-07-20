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

defmodule Hawk.LiveViewTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Hawk.LiveViewTest.{CourseIndexLive, CourseShowLive}
  alias Videdal.Course

  @course_id Videdal.course_id()
  @other_course_id Videdal.other_course_id()
  @school_admin_id Videdal.school_admin_id()
  @school_id Videdal.school_id()
  @student_id Videdal.student_id()
  @teacher_id Videdal.teacher_id()

  test "assign_index loads resources into predictable plural assigns" do
    courses = [%Course{id: @course_id, title: "Math"}]
    Process.put({Videdal.Repo, :all_results}, courses)

    socket =
      CourseIndexLive.assign_index(socket(), Authority.system(),
        page: %{column: :title, dir: :asc, size: 10}
      )

    assert socket.assigns.courses == courses
    assert socket.assigns.hawk_resource == :course
    assert socket.assigns.hawk_page == %{column: :title, dir: :asc, size: 10}

    assert socket.assigns.hawk_table == [
             %{name: :title, label: "Course"},
             %{name: :registration_state, label: "Registration"},
             %{name: :seat_count, label: "Seats"},
             %{name: :waitlist_count, label: "Waitlist"}
           ]

    assert_received {:videdal_repo, :all, query}
    assert inspect(query) =~ "order_by: [asc: c0.title]"
  end

  test "assign_index applies declared LiveView filters as reader narrowing" do
    courses = [%Course{id: @course_id, title: "Math", teacher_id: @teacher_id}]
    Process.put({Videdal.Repo, :all_results}, courses)

    socket =
      CourseIndexLive.assign_index(socket(), Authority.system(),
        params: %{"filter" => %{"teacher_id" => @teacher_id}}
      )

    assert socket.assigns.courses == courses
    assert_received {:videdal_repo, :all, query}
    assert inspect(query) =~ "c0.teacher_id == ^\"#{@teacher_id}\""
  end

  test "assign_index applies search, sort, and page params" do
    courses = [%Course{id: @course_id, title: "History", teacher_id: @teacher_id}]
    Process.put({Videdal.Repo, :all_results}, courses)

    socket =
      CourseIndexLive.assign_index(socket(), Authority.system(),
        params: %{
          "search" => %{"title" => "histo"},
          "sort" => "-title",
          "page" => %{"number" => "3", "size" => "10"}
        }
      )

    assert socket.assigns.courses == courses
    assert socket.assigns.hawk_page == %{column: :title, dir: :desc, number: 3, size: 10}
    assert socket.assigns.hawk_index_state.filter == %{title: {:ilike, "%histo%"}}
    assert_received {:videdal_repo, :all, query}
    inspected = inspect(query)
    assert inspected =~ "ilike(c0.title, ^\"%histo%\")"
    assert inspected =~ "desc: c0.title"
    assert inspected =~ "limit: ^10"
    assert inspected =~ "offset: ^20"
  end

  test "assign_index combines LiveView params with existing caller filters" do
    courses = [
      %Course{id: @course_id, title: "Math", school_id: @school_id, teacher_id: @teacher_id}
    ]

    Process.put({Videdal.Repo, :all_results}, courses)

    socket =
      CourseIndexLive.assign_index(socket(), Authority.system(),
        filter: %{school_id: @school_id},
        params: %{"filter" => %{"teacher_id" => @teacher_id}}
      )

    assert socket.assigns.courses == courses
    assert_received {:videdal_repo, :all, query}
    inspected = inspect(query)
    assert inspected =~ "c0.school_id == ^\"#{@school_id}\""
    assert inspected =~ "c0.teacher_id == ^\"#{@teacher_id}\""
  end

  test "assign_index rejects undeclared LiveView filters without creating atoms" do
    hostile = "hawk_hostile_live_filter_#{System.unique_integer([:positive])}"

    assert_raise ArgumentError, "unknown LiveView filter #{inspect(hostile)}", fn ->
      CourseIndexLive.assign_index(socket(), Authority.system(),
        params: %{"filter" => %{hostile => "boom"}}
      )
    end

    refute_existing_atom(hostile)
  end

  test "assign_show loads one resource into predictable singular assigns" do
    course = %Course{id: @course_id, title: "Math"}
    Process.put({Videdal.Repo, :all_results}, [course])

    socket = CourseShowLive.assign_show(socket(), Authority.system(), @course_id)

    assert socket.assigns.course == course
    assert socket.assigns.hawk_resource == :course

    assert socket.assigns.hawk_fields == [
             %{name: :title},
             %{name: :registration_state, label: "Registration"},
             %{name: :seat_count, label: "Seats"},
             %{name: :waitlist_count, label: "Waitlist"}
           ]

    assert_received {:videdal_repo, :all, query}
    assert inspect(query) =~ "c0.id == ^\"#{@course_id}\""
  end

  test "assign_show stores a LiveView-friendly error when the record is missing" do
    Process.put({Videdal.Repo, :all_results}, [])

    socket = CourseShowLive.assign_show(socket(), Authority.system(), @other_course_id)

    assert socket.assigns.hawk_error == %{base: ["course was not found"]}
  end

  test "assign_show merges an existing filter when loading one resource" do
    course = %Course{id: @course_id, title: "Math", school_id: @school_id}
    Process.put({Videdal.Repo, :all_results}, [course])

    socket =
      CourseShowLive.assign_show(socket(), Authority.system(), @course_id,
        filter: %{school_id: @school_id}
      )

    assert socket.assigns.course == course
    assert_received {:videdal_repo, :all, query}
    inspected = inspect(query)
    assert inspected =~ "c0.school_id == ^\"#{@school_id}\""
    assert inspected =~ "c0.id == ^\"#{@course_id}\""
  end

  test "assign_new_form assigns a keyed validation form without persisting" do
    socket = CourseIndexLive.assign_new_form(socket(), Authority.system())

    assert %Ecto.Changeset{action: :validate, valid?: false} = socket.assigns.course_form
    assert errors_on(socket.assigns.course_form).title == ["can't be blank"]
    assert socket.assigns.hawk_form_states.course.mode == :create
    refute_received {:videdal_repo, :insert, _changeset}
  end

  test "assign_edit_form assigns a keyed validation form for an existing model" do
    course = %Course{
      id: @course_id,
      title: "Math",
      school_id: @school_id,
      teacher_id: @teacher_id
    }

    socket = CourseIndexLive.assign_edit_form(socket(), course, Authority.system())

    assert %Ecto.Changeset{action: :validate, valid?: true} = socket.assigns.course_form
    assert socket.assigns.course_form.data == course
    assert socket.assigns.hawk_form_states.course.mode == :update
    assert socket.assigns.hawk_form_states.course.model == course
    refute_received {:videdal_repo, :update, _changeset}
  end

  test "validate event updates the create form with live errors" do
    socket = CourseIndexLive.assign_new_form(socket(), Authority.system())

    {:noreply, socket} =
      CourseIndexLive.handle_event("hawk:validate", %{"course" => %{"title" => ""}}, socket)

    assert %Ecto.Changeset{action: :validate, valid?: false} = socket.assigns.course_form
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

    assert %Ecto.Changeset{action: :validate, valid?: false} = socket.assigns.course_form
    assert errors_on(socket.assigns.course_form).title == ["is reserved"]
    refute_received {:videdal_repo, :update, _changeset}
  end

  test "save event creates, assigns the saved model, and switches form state to edit" do
    socket = CourseIndexLive.assign_new_form(socket(), Authority.system())

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

    assert %Course{title: "History", school_id: @school_id, teacher_id: @teacher_id} =
             socket.assigns.course

    assert %Ecto.Changeset{action: :validate, valid?: true} = socket.assigns.course_form
    assert socket.assigns.hawk_form_states.course.mode == :update
    assert socket.assigns.hawk_form_states.course.model == socket.assigns.course
    assert_received {:videdal_repo, :insert, %Ecto.Changeset{valid?: true}}
  end

  test "save event keeps create form with insert errors when create is invalid" do
    socket = CourseIndexLive.assign_new_form(socket(), Authority.system())

    {:noreply, socket} =
      CourseIndexLive.handle_event("hawk:save", %{"course" => %{"title" => ""}}, socket)

    assert %Ecto.Changeset{action: :insert, valid?: false} = socket.assigns.course_form
    assert errors_on(socket.assigns.course_form).title == ["can't be blank"]
    assert socket.assigns.hawk_form_states.course.mode == :create
    refute_received {:videdal_repo, :insert, _changeset}
  end

  test "save event updates and assigns the saved model" do
    course = %Course{
      id: @course_id,
      title: "Math",
      school_id: @school_id,
      teacher_id: @teacher_id
    }

    socket = CourseIndexLive.assign_edit_form(socket(), course, Authority.system())

    {:noreply, socket} =
      CourseIndexLive.handle_event("hawk:save", %{"course" => %{"title" => "History"}}, socket)

    assert %Course{id: @course_id, title: "History"} = socket.assigns.course
    assert socket.assigns.hawk_form_states.course.mode == :update
    assert socket.assigns.hawk_form_states.course.model == socket.assigns.course
    assert_received {:videdal_repo, :update, %Ecto.Changeset{valid?: true}}
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

    assert %Ecto.Changeset{action: :update, valid?: false} = socket.assigns.course_form
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
    course = %Course{id: @course_id, title: "Math"}
    Process.put({Videdal.Repo, :all_results}, [course])

    {:noreply, socket} =
      CourseIndexLive.handle_event(
        "hawk:delete",
        %{
          "id" => @course_id,
          "authority" =>
            Authority.new(:school_admin, @school_admin_id, scopes: %{school_id: @school_id})
        },
        socket()
      )

    assert socket.assigns.courses == [course]
    assert_received {:videdal_repo, :delete, %Course{id: @course_id}}
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
    course = %Course{id: @course_id, title: "Math", school_id: @school_id}
    Process.put({Videdal.Repo, :all_results}, [course])

    {:noreply, socket} =
      CourseIndexLive.handle_event(
        "hawk:delete",
        %{
          "id" => @course_id,
          "authority" => Authority.new(:student, @student_id, scopes: %{school_id: @school_id})
        },
        socket()
      )

    assert socket.assigns.hawk_error == %{base: ["You are not allowed to delete this course."]}
  end

  defp socket do
    %{assigns: %{}}
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  defp refute_existing_atom(value) do
    _existing = String.to_existing_atom(value)
    flunk("expected #{inspect(value)} not to be an existing atom")
  rescue
    ArgumentError -> :ok
  end
end
