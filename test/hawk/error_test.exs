defmodule Hawk.ErrorTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Hawk.Errors
  alias Videdal.{Grade, Grades}

  test "unauthorized writer results carry a useful operation-aware error" do
    grade = %Grade{id: 1, score: 10, school_id: 7, student_id: 8, course_id: 3}
    authority = Authority.new(:parent, 4, scopes: %{school_id: 7, parent_id: 4})

    assert {:not_authorized, context} = Grades.update(grade, %{score: 12}, authority)

    assert context.operation == :update

    assert context.meta.authorization_error == %{
             code: :not_authorized,
             title: "Not authorized",
             detail: "You are not allowed to update this grade."
           }
  end

  test "unauthorized results convert to JSON:API errors" do
    grade = %Grade{id: 1, score: 10, school_id: 7, student_id: 8, course_id: 3}
    authority = Authority.new(:parent, 4, scopes: %{school_id: 7, parent_id: 4})

    result = Grades.update(grade, %{score: 12}, authority)

    assert Errors.to_json_api(result) == %{
             errors: [
               %{
                 status: "403",
                 code: "not_authorized",
                 title: "Not authorized",
                 detail: "You are not allowed to update this grade."
               }
             ]
           }
  end

  test "invalid results convert to JSON:API source pointers" do
    authority = Authority.new(:teacher, 12, scopes: %{school_id: 7, teacher_id: 12})

    result = Grades.create(%{score: 12, school_id: 7, student_id: 8}, authority)

    assert %{errors: [error]} = Errors.to_json_api(result)
    assert error.status == "422"
    assert error.code == "invalid"
    assert error.source == %{pointer: "/data/attributes/course_id"}
    assert error.detail =~ "can't be blank"
  end

  test "invalid results convert to LiveView-friendly errors" do
    authority = Authority.new(:teacher, 12, scopes: %{school_id: 7, teacher_id: 12})

    result = Grades.create(%{score: 12, school_id: 7, student_id: 8}, authority)

    assert Errors.to_live_view(result) == {:error, %{course_id: ["can't be blank"]}}
  end
end
