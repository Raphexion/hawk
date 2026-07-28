defmodule Hawk.WriterResourceTest.CourseWriter do
  use Hawk.Writer.Resource,
    model: Videdal.Course,
    repo: Videdal.Repo,
    policy: Videdal.Courses.Policy

  create do
    defaults(seat_count: 12)
    cast([:title, :school_id, :teacher_id, :seat_count])
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
  use Videdal.DatabaseCase, async: true

  alias Ecto.Changeset
  alias Hawk.Authority
  alias Hawk.WriterResourceTest.CourseWriter
  alias Videdal.Course

  test "generated change_create returns the create pipeline changeset without persisting" do
    changeset =
      CourseWriter.change_create(%{"title" => "", "school_id" => Ecto.UUID.generate()}, Authority.system())

    assert %Changeset{action: :validate, valid?: false} = changeset
    assert errors_on(changeset).title == ["can't be blank"]
  end

  test "generated change_update returns the update pipeline changeset without persisting" do
    course = insert(:course)

    changeset = CourseWriter.change_update(course, %{"title" => "History"}, Authority.system())

    assert %Changeset{action: :validate, valid?: true} = changeset
    assert changeset.data.id == course.id
    assert Changeset.get_change(changeset, :title) == "History"
  end

  test "generated update persists through the same update pipeline" do
    course = insert(:course)

    assert {:ok, %Course{title: "History"} = updated} =
             CourseWriter.update(course, %{"title" => "History"}, Authority.system())

    assert updated.id == course.id
  end

  test "generated create and update reuse custom validation functions" do
    attrs = %{"title" => "Forbidden", "school_id" => Ecto.UUID.generate(), "teacher_id" => Ecto.UUID.generate()}

    course = insert(:course)

    create_changeset = CourseWriter.change_create(attrs, Authority.system())

    update_changeset =
      CourseWriter.change_update(course, %{"title" => "Forbidden"}, Authority.system())

    assert errors_on(create_changeset).title == ["is reserved"]
    assert errors_on(update_changeset).title == ["is reserved"]
  end

  test "generated create persists through the same create pipeline" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)

    attrs = %{"title" => "History", "school_id" => school.id, "teacher_id" => teacher.id}

    assert {:ok, %Course{title: "History", seat_count: 12} = created} =
             CourseWriter.create(attrs, Authority.system())

    assert created.school_id == school.id
    assert created.teacher_id == teacher.id
  end

  defp errors_on(changeset) do
    Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
