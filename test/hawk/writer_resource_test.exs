defmodule Hawk.WriterResourceTest.CourseWriter do
  use Hawk.Writer.Resource,
    model: Videdal.Course,
    repo: Videdal.Repo,
    policy: Videdal.Courses.Policy

  create do
    cast([:title, :school_id, :teacher_id])
    validate_required([:title, :school_id, :teacher_id])
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
