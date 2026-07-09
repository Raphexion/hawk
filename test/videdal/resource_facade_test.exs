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

  @course_id Videdal.course_id()
  @enrollment_id Videdal.enrollment_id()
  @grade_id Videdal.grade_id()
  @school_admin_id Videdal.school_admin_id()
  @school_id Videdal.school_id()
  @student_id Videdal.student_id()
  @teacher_id Videdal.teacher_id()

  test "read facades expose one/1 and one!/1 for controller and LiveView style callers" do
    grade = %Grade{
      id: @grade_id,
      score: 12,
      school_id: @school_id,
      student_id: @student_id,
      course_id: @course_id
    }

    Process.put({Videdal.Repo, :all_results}, [grade])

    assert Grades.one!(authority: Authority.system(), filter: %{id: @grade_id}) == grade

    summary = %CourseGradeSummary{
      id: @course_id,
      school_id: @school_id,
      course_id: @course_id,
      grade_count: 2
    }

    Process.put({Videdal.Repo, :all_results}, [summary])

    assert CourseGradeSummaries.one(
             authority: Authority.system(),
             filter: %{course_id: @course_id}
           ) ==
             {:ok, summary}

    assert CourseGradeSummaries.one!(
             authority: Authority.system(),
             filter: %{course_id: @course_id}
           ) ==
             summary

    enrollment = %Enrollment{
      id: @enrollment_id,
      school_id: @school_id,
      student_id: @student_id,
      course_id: @course_id
    }

    Process.put({Videdal.Repo, :all_results}, [enrollment])

    assert Enrollments.one(authority: Authority.system(), filter: %{id: @enrollment_id}) ==
             {:ok, enrollment}

    assert Enrollments.one!(authority: Authority.system(), filter: %{id: @enrollment_id}) ==
             enrollment

    teacher = %Teacher{id: @teacher_id, name: "Grace", school_id: @school_id}
    Process.put({Videdal.Repo, :all_results}, [teacher])

    assert Teachers.one(authority: Authority.system(), filter: %{id: @teacher_id}) ==
             {:ok, teacher}

    assert Teachers.one!(authority: Authority.system(), filter: %{id: @teacher_id}) == teacher
  end

  test "course grade summary facade keeps read-only writer errors at resource boundary" do
    summary = %CourseGradeSummary{
      id: @course_id,
      school_id: @school_id,
      course_id: @course_id,
      grade_count: 2
    }

    authority = Authority.new(:school_admin, @school_admin_id, scopes: %{school_id: @school_id})

    assert {:not_authorized, create_context} = CourseGradeSummaries.create(%{}, authority)
    assert create_context.operation == :create

    assert {:not_authorized, update_context} =
             CourseGradeSummaries.update(summary, %{}, authority)

    assert update_context.operation == :update

    assert {:not_authorized, delete_context} = CourseGradeSummaries.delete(summary, authority)
    assert delete_context.operation == :delete
  end

  test "enrollment and teacher facades delegate mutations through their writers" do
    authority = Authority.new(:school_admin, @school_admin_id, scopes: %{school_id: @school_id})

    assert {:ok, enrollment} =
             Enrollments.create(
               %{
                 school_id: @school_id,
                 student_id: @student_id,
                 course_id: @course_id,
                 enrolled_on: ~D[2026-01-01]
               },
               authority
             )

    assert enrollment.school_id == @school_id
    assert_received {:videdal_repo, :insert, _changeset}

    assert {:ok, teacher} = Teachers.create(%{name: "Grace", school_id: @school_id}, authority)
    assert teacher.name == "Grace"
    assert_received {:videdal_repo, :insert, _changeset}
  end
end
