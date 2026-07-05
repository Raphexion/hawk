defmodule Videdal.ResourceFacadeTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority

  alias Videdal.{
    CourseGradeSummaries,
    CourseGradeSummary,
    Enrollment,
    Enrollments,
    Grade,
    Grades,
    Teacher,
    Teachers
  }

  test "read facades expose one/1 and one!/1 for controller and LiveView style callers" do
    grade = %Grade{id: 3, score: 12, school_id: 7, student_id: 8, course_id: 3}
    Process.put({Videdal.Repo, :all_results}, [grade])

    assert Grades.one!(authority: Authority.system(), filter: %{id: 3}) == grade

    summary = %CourseGradeSummary{id: 3, school_id: 7, course_id: 3, grade_count: 2}
    Process.put({Videdal.Repo, :all_results}, [summary])

    assert CourseGradeSummaries.one(authority: Authority.system(), filter: %{course_id: 3}) ==
             {:ok, summary}

    assert CourseGradeSummaries.one!(authority: Authority.system(), filter: %{course_id: 3}) ==
             summary

    enrollment = %Enrollment{id: 4, school_id: 7, student_id: 8, course_id: 3}
    Process.put({Videdal.Repo, :all_results}, [enrollment])

    assert Enrollments.one(authority: Authority.system(), filter: %{id: 4}) == {:ok, enrollment}
    assert Enrollments.one!(authority: Authority.system(), filter: %{id: 4}) == enrollment

    teacher = %Teacher{id: 12, name: "Grace", school_id: 7}
    Process.put({Videdal.Repo, :all_results}, [teacher])

    assert Teachers.one(authority: Authority.system(), filter: %{id: 12}) == {:ok, teacher}
    assert Teachers.one!(authority: Authority.system(), filter: %{id: 12}) == teacher
  end

  test "course grade summary facade keeps read-only writer errors at resource boundary" do
    summary = %CourseGradeSummary{id: 3, school_id: 7, course_id: 3, grade_count: 2}
    authority = Authority.new(:school_admin, 1, scopes: %{school_id: 7})

    assert {:not_authorized, create_context} = CourseGradeSummaries.create(%{}, authority)
    assert create_context.operation == :create

    assert {:not_authorized, update_context} =
             CourseGradeSummaries.update(summary, %{}, authority)

    assert update_context.operation == :update

    assert {:not_authorized, delete_context} = CourseGradeSummaries.delete(summary, authority)
    assert delete_context.operation == :delete
  end

  test "enrollment and teacher facades delegate mutations through their writers" do
    authority = Authority.new(:school_admin, 1, scopes: %{school_id: 7})

    assert {:ok, enrollment} =
             Enrollments.create(
               %{school_id: 7, student_id: 8, course_id: 3, enrolled_on: ~D[2026-01-01]},
               authority
             )

    assert enrollment.school_id == 7
    assert_received {:videdal_repo, :insert, _changeset}

    assert {:ok, teacher} = Teachers.create(%{name: "Grace", school_id: 7}, authority)
    assert teacher.name == "Grace"
    assert_received {:videdal_repo, :insert, _changeset}
  end
end
