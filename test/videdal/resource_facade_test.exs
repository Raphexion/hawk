defmodule Videdal.ResourceFacadeTest do
  use ExUnit.Case, async: true

  alias Hawk.Authority

  alias Videdal.Course
  alias Videdal.CourseGradeSummaries
  alias Videdal.CourseGradeSummary
  alias Videdal.Courses
  alias Videdal.Courses.{JsonApi, LiveView}
  alias Videdal.Enrollment
  alias Videdal.Enrollments
  alias Videdal.Grade
  alias Videdal.Grades
  alias Videdal.School
  alias Videdal.Schools
  alias Videdal.Student
  alias Videdal.Students
  alias Videdal.Teacher
  alias Videdal.Teachers

  @course_id Videdal.course_id()
  @enrollment_id Videdal.enrollment_id()
  @grade_id Videdal.grade_id()
  @school_admin_id Videdal.school_admin_id()
  @school_id Videdal.school_id()
  @school_name "Videdal Skole"
  @student_id Videdal.student_id()
  @teacher_id Videdal.teacher_id()

  test "read facades expose one/1 and one!/1 for controller and LiveView style callers" do
    course = %Course{
      id: @course_id,
      title: "Math",
      school_id: @school_id,
      teacher_id: @teacher_id,
      registration_state: "draft",
      seat_count: 0,
      waitlist_count: 0
    }

    Process.put({Videdal.Repo, :all_results}, [course])

    assert Courses.one(authority: Authority.system(), filter: %{id: @course_id}) == {:ok, course}
    assert Courses.one!(authority: Authority.system(), filter: %{id: @course_id}) == course

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

  test "course facade exposes resource metadata from sibling adapter modules" do
    assert Courses.__hawk_resource__(:model) == Course
    assert Courses.__hawk_resource__(:reader) == Videdal.Courses.Reader
    assert Courses.__hawk_resource__(:policy) == Videdal.Courses.Policy
    assert Courses.__hawk_resource__(:writer) == Videdal.Courses.Writer
    assert Courses.__hawk_resource__(:actions) == Videdal.Courses.Actions
    assert Courses.__hawk_resource__(:json_api) == Videdal.Courses.JsonApi
    assert Courses.__hawk_resource__(:live_view) == Videdal.Courses.LiveView

    assert JsonApi.__hawk_json_api__().type == "courses"
    assert LiveView.__hawk_live_view__().as == :course
  end

  test "course facade delegates reads, CRUD mutations, and actions through sibling modules" do
    authority = Authority.new(:school_admin, @school_admin_id, scopes: %{school_id: @school_id})

    Process.put({Videdal.Repo, :all_results}, [
      %Course{
        id: @course_id,
        title: "Math",
        school_id: @school_id,
        teacher_id: @teacher_id,
        registration_state: "draft",
        seat_count: 0,
        waitlist_count: 0
      }
    ])

    assert [%Course{id: @course_id}] = Courses.all(authority: Authority.system())
    assert_received {:videdal_repo, :all, _query}

    assert {:ok, created_course} =
             Courses.create(
               %{title: "Math", school_id: @school_id, teacher_id: @teacher_id},
               authority
             )

    assert created_course.title == "Math"
    assert_received {:videdal_repo, :insert, _changeset}

    course = %Course{
      id: @course_id,
      title: "Math",
      school_id: @school_id,
      teacher_id: @teacher_id,
      registration_state: "draft",
      seat_count: 0,
      waitlist_count: 0
    }

    assert {:ok, %Course{title: "Advanced Math"}} =
             Courses.update(course, %{title: "Advanced Math"}, authority)

    assert_received {:videdal_repo, :update, _changeset}

    assert {:ok, opened_course} =
             Courses.open_registration(course, %{seat_count: 2, waitlist_count: 1}, authority)

    assert opened_course.registration_state == "open"
    assert opened_course.seat_count == 2
    assert opened_course.waitlist_count == 1
    assert_received {:videdal_repo, :update, _changeset}

    open_course = %{course | registration_state: "open", seat_count: 2, waitlist_count: 1}

    enrollments = [
      %Enrollment{
        id: "enrollment-1",
        school_id: @school_id,
        course_id: @course_id,
        student_id: @student_id,
        enrolled_on: ~D[2026-01-01],
        registration_status: "pending"
      },
      %Enrollment{
        id: "enrollment-2",
        school_id: @school_id,
        course_id: @course_id,
        student_id: Videdal.other_student_id(),
        enrolled_on: ~D[2026-01-02],
        registration_status: "pending"
      },
      %Enrollment{
        id: "enrollment-3",
        school_id: @school_id,
        course_id: @course_id,
        student_id: "00000000-0000-0000-0000-000000000011",
        enrolled_on: ~D[2026-01-03],
        registration_status: "pending"
      }
    ]

    Process.put({Videdal.Repo, :all_results, Videdal.Enrollment}, enrollments)

    assert {:ok, closed_course} = Courses.close_registration(open_course, %{}, authority)
    assert closed_course.registration_state == "closed"
    assert_received {:videdal_repo, :transaction}

    assert {:ok, deleted_course} = Courses.delete(course, authority)
    assert deleted_course.id == @course_id
    assert_received {:videdal_repo, :delete, _course}
  end

  test "school and student facades delegate reads and CRUD mutations through sibling modules" do
    school_authority = Authority.new(:principal, Videdal.principal_id())

    student_authority =
      Authority.new(:school_admin, @school_admin_id, scopes: %{school_id: @school_id})

    school = %School{id: @school_id, name: @school_name}
    Process.put({Videdal.Repo, :all_results}, [school])

    assert Schools.one(authority: Authority.system(), filter: %{id: @school_id}) == {:ok, school}
    assert Schools.one!(authority: Authority.system(), filter: %{id: @school_id}) == school
    assert [^school] = Schools.all(authority: Authority.system())
    assert_received {:videdal_repo, :all, _query}

    assert {:ok, created_school} = Schools.create(%{name: @school_name}, school_authority)
    assert created_school.name == @school_name
    assert_received {:videdal_repo, :insert, _changeset}

    assert {:ok, updated_school} =
             Schools.update(school, %{name: "Malmö Academy"}, school_authority)

    assert updated_school.name == "Malmö Academy"
    assert_received {:videdal_repo, :update, _changeset}

    assert {:ok, deleted_school} = Schools.delete(school, school_authority)
    assert deleted_school.id == @school_id
    assert_received {:videdal_repo, :delete, ^school}

    student = %Student{id: @student_id, name: "Ada", active: true, school_id: @school_id}
    Process.put({Videdal.Repo, :all_results}, [student])

    assert Students.one(authority: Authority.system(), filter: %{id: @student_id}) ==
             {:ok, student}

    assert Students.one!(authority: Authority.system(), filter: %{id: @student_id}) == student
    assert [^student] = Students.all(authority: Authority.system())
    assert_received {:videdal_repo, :all, _query}

    assert {:ok, created_student} =
             Students.create(
               %{name: "Ada", active: true, school_id: @school_id},
               student_authority
             )

    assert created_student.name == "Ada"
    assert_received {:videdal_repo, :insert, _changeset}

    assert {:ok, updated_student} =
             Students.update(student, %{name: "Ada Lovelace", active: false}, student_authority)

    assert updated_student.name == "Ada Lovelace"
    assert updated_student.active == false
    assert_received {:videdal_repo, :update, _changeset}

    assert {:ok, deleted_student} = Students.delete(student, student_authority)
    assert deleted_student.id == @student_id
    assert_received {:videdal_repo, :delete, ^student}
  end

  test "grade facade delegates reads and CRUD mutations through sibling modules" do
    authority =
      Authority.new(:teacher, @teacher_id, scopes: %{school_id: @school_id, teacher_id: @teacher_id})

    grade = %Grade{
      id: @grade_id,
      score: 12,
      school_id: @school_id,
      student_id: @student_id,
      course_id: @course_id
    }

    Process.put({Videdal.Repo, :all_results}, [grade])

    assert Grades.one(authority: Authority.system(), filter: %{id: @grade_id}) == {:ok, grade}
    assert Grades.one!(authority: Authority.system(), filter: %{id: @grade_id}) == grade
    assert [^grade] = Grades.all(authority: Authority.system())
    assert_received {:videdal_repo, :all, _query}

    assert {:ok, created_grade} =
             Grades.create(
               %{
                 score: 12,
                 school_id: @school_id,
                 student_id: @student_id,
                 course_id: @course_id
               },
               authority
             )

    assert created_grade.score == 12
    assert_received {:videdal_repo, :insert, _changeset}

    assert {:ok, updated_grade} = Grades.update(grade, %{score: 15}, authority)
    assert updated_grade.score == 15
    assert_received {:videdal_repo, :update, _changeset}

    assert {:ok, deleted_grade} = Grades.delete(grade, authority)
    assert deleted_grade.id == @grade_id
    assert_received {:videdal_repo, :delete, ^grade}
  end

  test "enrollment and teacher facades delegate mutations through their writers" do
    authority = Authority.new(:school_admin, @school_admin_id, scopes: %{school_id: @school_id})

    enrollment = %Enrollment{
      id: @enrollment_id,
      school_id: @school_id,
      student_id: @student_id,
      course_id: @course_id,
      enrolled_on: ~D[2026-01-01],
      registration_status: "pending"
    }

    Process.put({Videdal.Repo, :all_results}, [enrollment])

    assert Enrollments.one(authority: Authority.system(), filter: %{id: @enrollment_id}) ==
             {:ok, enrollment}

    assert Enrollments.one!(authority: Authority.system(), filter: %{id: @enrollment_id}) ==
             enrollment

    assert [^enrollment] = Enrollments.all(authority: Authority.system())
    assert_received {:videdal_repo, :all, _query}

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

    assert {:ok, updated_enrollment} =
             Enrollments.update(enrollment, %{enrolled_on: ~D[2026-02-01]}, authority)

    assert updated_enrollment.enrolled_on == ~D[2026-02-01]
    assert_received {:videdal_repo, :update, _changeset}

    assert {:ok, deleted_enrollment} = Enrollments.delete(enrollment, authority)
    assert deleted_enrollment.id == enrollment.id
    assert_received {:videdal_repo, :delete, _enrollment}

    teacher = %Teacher{id: @teacher_id, name: "Grace", school_id: @school_id}
    Process.put({Videdal.Repo, :all_results}, [teacher])

    assert Teachers.one(authority: Authority.system(), filter: %{id: @teacher_id}) ==
             {:ok, teacher}

    assert Teachers.one!(authority: Authority.system(), filter: %{id: @teacher_id}) == teacher
    assert [^teacher] = Teachers.all(authority: Authority.system())
    assert_received {:videdal_repo, :all, _query}

    assert {:ok, created_teacher} =
             Teachers.create(%{name: "Grace", school_id: @school_id}, authority)

    assert created_teacher.name == "Grace"
    assert_received {:videdal_repo, :insert, _changeset}

    assert {:ok, updated_teacher} = Teachers.update(teacher, %{name: "Grace Hopper"}, authority)
    assert updated_teacher.name == "Grace Hopper"
    assert_received {:videdal_repo, :update, _changeset}

    assert {:ok, deleted_teacher} = Teachers.delete(teacher, authority)
    assert deleted_teacher.id == @teacher_id
    assert_received {:videdal_repo, :delete, _teacher}
  end
end
