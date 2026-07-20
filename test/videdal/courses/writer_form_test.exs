defmodule Videdal.Courses.WriterFormTest do
  use ExUnit.Case, async: true

  alias Ecto.Changeset
  alias Hawk.Authority
  alias Videdal.{Course, Courses}
  alias Videdal.Courses.Writer

  @school_id Videdal.school_id()
  @teacher_id Videdal.teacher_id()

  test "change_create returns a non-persisting changeset with live validation errors" do
    changeset =
      Writer.change_create(%{"title" => "", "school_id" => @school_id}, Authority.system())

    assert %Changeset{action: :validate, valid?: false} = changeset
    assert errors_on(changeset).title == ["can't be blank"]
    refute_received {:videdal_repo, :insert, _changeset}
  end

  test "change_create uses the same casting and validation as create" do
    changeset =
      Writer.change_create(
        %{"title" => "History", "school_id" => @school_id, "teacher_id" => @teacher_id},
        Authority.system()
      )

    assert %Changeset{action: :validate, valid?: true} = changeset
    assert Changeset.get_change(changeset, :title) == "History"
    assert Changeset.get_change(changeset, :school_id) == @school_id
    assert Changeset.get_change(changeset, :teacher_id) == @teacher_id
  end

  test "change_update returns a non-persisting changeset for an existing model" do
    course = %Course{
      id: Videdal.course_id(),
      title: "Math",
      school_id: @school_id,
      teacher_id: @teacher_id
    }

    changeset = Writer.change_update(course, %{"title" => "History"}, Authority.system())

    assert %Changeset{action: :validate, valid?: true} = changeset
    assert changeset.data == course
    assert Changeset.get_change(changeset, :title) == "History"
    refute_received {:videdal_repo, :update, _changeset}
  end

  test "resource facade delegates form changeset helpers" do
    changeset = Courses.change_create(%{"title" => ""}, Authority.system())

    assert %Changeset{action: :validate, valid?: false} = changeset
    assert errors_on(changeset).title == ["can't be blank"]
  end

  defp errors_on(changeset) do
    Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
