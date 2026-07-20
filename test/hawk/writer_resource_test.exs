defmodule Hawk.WriterResourceTest.CourseWriter do
  use Hawk.Writer.Resource,
    model: Videdal.Course,
    repo: Videdal.Repo,
    policy: Videdal.Courses.Policy

  create do
    cast([:title, :school_id, :teacher_id])
    validate_required([:title, :school_id, :teacher_id])
    validate(&reject_reserved_title/1)
  end

  update do
    cast([:title, :school_id, :teacher_id])
    validate(&reject_reserved_title/1)
  end

  defp reject_reserved_title(context) do
    case Ecto.Changeset.get_change(context.changeset, :title) do
      "Forbidden" -> {:error, :title, "is reserved"}
      _title -> :ok
    end
  end
end

defmodule Hawk.WriterResourceTest do
  use ExUnit.Case, async: true

  alias Ecto.Changeset
  alias Hawk.Authority
  alias Hawk.WriterResourceTest.CourseWriter
  alias Videdal.Course

  @school_id Videdal.school_id()
  @teacher_id Videdal.teacher_id()

  test "generated change_create returns the create pipeline changeset without persisting" do
    changeset =
      CourseWriter.change_create(%{"title" => "", "school_id" => @school_id}, Authority.system())

    assert %Changeset{action: :validate, valid?: false} = changeset
    assert errors_on(changeset).title == ["can't be blank"]
    refute_received {:videdal_repo, :insert, _changeset}
  end

  test "generated change_update returns the update pipeline changeset without persisting" do
    course = %Course{
      id: Videdal.course_id(),
      title: "Math",
      school_id: @school_id,
      teacher_id: @teacher_id
    }

    changeset = CourseWriter.change_update(course, %{"title" => "History"}, Authority.system())

    assert %Changeset{action: :validate, valid?: true} = changeset
    assert changeset.data == course
    assert Changeset.get_change(changeset, :title) == "History"
    refute_received {:videdal_repo, :update, _changeset}
  end

  test "generated update persists through the same update pipeline" do
    course = %Course{
      id: Videdal.course_id(),
      title: "Math",
      school_id: @school_id,
      teacher_id: @teacher_id
    }

    assert {:ok, %Course{title: "History", school_id: @school_id, teacher_id: @teacher_id}} =
             CourseWriter.update(course, %{"title" => "History"}, Authority.system())

    assert_received {:videdal_repo, :update, %Changeset{} = changeset}
    assert changeset.valid?
    assert changeset.data == course
    assert Changeset.get_change(changeset, :title) == "History"
  end

  test "generated create and update reuse custom validation functions" do
    attrs = %{"title" => "Forbidden", "school_id" => @school_id, "teacher_id" => @teacher_id}

    course = %Course{
      id: Videdal.course_id(),
      title: "Math",
      school_id: @school_id,
      teacher_id: @teacher_id
    }

    create_changeset = CourseWriter.change_create(attrs, Authority.system())

    update_changeset =
      CourseWriter.change_update(course, %{"title" => "Forbidden"}, Authority.system())

    assert errors_on(create_changeset).title == ["is reserved"]
    assert errors_on(update_changeset).title == ["is reserved"]
    refute_received {:videdal_repo, :insert, _changeset}
    refute_received {:videdal_repo, :update, _changeset}
  end

  test "generated create persists through the same create pipeline" do
    attrs = %{"title" => "History", "school_id" => @school_id, "teacher_id" => @teacher_id}

    assert {:ok, %Course{title: "History", school_id: @school_id, teacher_id: @teacher_id}} =
             CourseWriter.create(attrs, Authority.system())

    assert_received {:videdal_repo, :insert, %Changeset{} = changeset}
    assert changeset.valid?
    assert Changeset.get_change(changeset, :title) == "History"
  end

  defp errors_on(changeset) do
    Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
