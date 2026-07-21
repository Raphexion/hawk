defmodule Hawk.ErrorTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority
  alias Hawk.Errors
  alias Hawk.MutationContext
  alias Videdal.{Grade, Grades, Student}

  @course_id Videdal.course_id()
  @grade_id Videdal.grade_id()
  @parent_id Videdal.parent_id()
  @school_id Videdal.school_id()
  @student_id Videdal.student_id()
  @teacher_id Videdal.teacher_id()

  test "unauthorized writer results carry a canonical operation-aware error" do
    grade = %Grade{
      id: @grade_id,
      score: 10,
      school_id: @school_id,
      student_id: @student_id,
      course_id: @course_id
    }

    authority =
      Authority.new(:parent, @parent_id, scopes: %{school_id: @school_id, parent_id: @parent_id})

    assert {:not_authorized, context} = Grades.update(grade, %{score: 12}, authority)

    assert context.operation == :update

    assert context.meta.authorization_error == %Hawk.Error{
             status: 403,
             code: :not_authorized,
             title: "Not authorized",
             detail: "You are not allowed to update this grade.",
             source: nil
           }
  end

  test "unauthorized results convert to JSON:API errors" do
    grade = %Grade{
      id: @grade_id,
      score: 10,
      school_id: @school_id,
      student_id: @student_id,
      course_id: @course_id
    }

    authority =
      Authority.new(:parent, @parent_id, scopes: %{school_id: @school_id, parent_id: @parent_id})

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
    authority =
      Authority.new(:teacher, @teacher_id, scopes: %{school_id: @school_id, teacher_id: @teacher_id})

    result =
      Grades.create(%{score: 12, school_id: @school_id, student_id: @student_id}, authority)

    assert %{errors: [error]} = Errors.to_json_api(result)
    assert error.status == "422"
    assert error.code == "invalid"
    assert error.source == %{pointer: "/data/attributes/course_id"}
    assert error.detail =~ "can't be blank"
  end

  test "invalid results convert to LiveView-friendly errors" do
    authority =
      Authority.new(:teacher, @teacher_id, scopes: %{school_id: @school_id, teacher_id: @teacher_id})

    result =
      Grades.create(%{score: 12, school_id: @school_id, student_id: @student_id}, authority)

    assert Errors.to_live_view(result) == {:error, %{course_id: ["can't be blank"]}}
  end

  test "invalid results tolerate non-stringable validation metadata" do
    type = {:parameterized, {Ecto.Enum, %{mappings: [web: "web"]}}}

    context =
      %Student{}
      |> MutationContext.create(%{}, Authority.system())
      |> MutationContext.add_error(:app_name, "is invalid for %{type}", type: type)

    assert %{errors: [%{detail: detail}]} = Errors.to_json_api({:invalid, context})
    assert detail =~ "is invalid for"
    assert detail =~ "Ecto.Enum"
  end

  test "errors expose canonical structs before adapter rendering" do
    assert [error] = Errors.to_errors(Hawk.Error.bad_request("bad filter"))

    assert error == %Hawk.Error{
             status: 400,
             code: :bad_request,
             title: "Bad request",
             detail: "bad filter",
             source: nil
           }

    assert Errors.to_json_api(error) == %{
             errors: [
               %{status: "400", code: "bad_request", title: "Bad request", detail: "bad filter"}
             ]
           }
  end
end
