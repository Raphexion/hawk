defmodule Videdal.ResourceFacadeTest do
  use Videdal.DatabaseCase, async: true

  alias Hawk.Authority

  alias Videdal.Course
  alias Videdal.CourseGradeSummaries
  alias Videdal.CourseGradeSummary
  alias Videdal.Courses
  alias Videdal.Courses.{JsonApi, LiveView}
  alias Videdal.Enrollments
  alias Videdal.Grades
  alias Videdal.Schools
  alias Videdal.Students
  alias Videdal.Teachers

  @school_admin_id Videdal.school_admin_id()
  @school_name "Videdal Skole"

  test "read facades expose one/1 for controller and LiveView style callers" do
    course = insert(:course, title: "Math")

    assert {:ok, found} = Courses.one(authority: Authority.system(), filter: %{id: course.id})
    assert found.id == course.id
    assert found.title == "Math"

    grade = insert(:grade, score: 12)

    assert {:ok, found} = Grades.one(authority: Authority.system(), filter: %{id: grade.id})
    assert found.id == grade.id
    assert found.score == 12

    summary_course = insert(:course)
    summary_student = insert(:student, school_id: summary_course.school_id)

    insert(:grade,
      course_id: summary_course.id,
      school_id: summary_course.school_id,
      student_id: summary_student.id,
      score: 12
    )

    insert(:grade,
      course_id: summary_course.id,
      school_id: summary_course.school_id,
      student_id: summary_student.id,
      score: 10
    )

    assert {:ok, summary} =
             CourseGradeSummaries.one(
               authority: Authority.system(),
               filter: %{course_id: summary_course.id}
             )

    assert summary.course_id == summary_course.id
    assert summary.grade_count == 2

    enrollment = insert(:enrollment)

    assert {:ok, found} =
             Enrollments.one(authority: Authority.system(), filter: %{id: enrollment.id})

    assert found.id == enrollment.id

    teacher = insert(:teacher)

    assert {:ok, found} = Teachers.one(authority: Authority.system(), filter: %{id: teacher.id})
    assert found.id == teacher.id
    assert found.name == teacher.name
  end

  test "course grade summary facade keeps read-only writer errors at resource boundary" do
    summary = %CourseGradeSummary{
      id: Ecto.UUID.generate(),
      school_id: Ecto.UUID.generate(),
      course_id: Ecto.UUID.generate(),
      grade_count: 2
    }

    authority =
      Authority.new(:school_admin, @school_admin_id, scopes: %{school_id: summary.school_id})

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

  test "course facade delegates reads, CRUD mutations, and action dispatch through sibling modules" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)
    school_id = school.id

    authority =
      Authority.new(:school_admin, @school_admin_id, scopes: %{school_id: school_id})

    course = insert(:course, school_id: school_id, teacher_id: teacher.id, title: "Math")

    assert course.id in Enum.map(Courses.all(authority: Authority.system()), & &1.id)

    assert {:ok, created} =
             Courses.create(
               %{title: "Math", school_id: school_id, teacher_id: teacher.id},
               authority
             )

    assert created.title == "Math"

    assert {:ok, updated} = Courses.update(course, %{title: "Advanced Math"}, authority)
    assert updated.title == "Advanced Math"

    assert {:ok, opened} =
             Courses.action("open-registration", course, %{seat_count: 2, waitlist_count: 1}, authority)

    assert opened.registration_state == "open"
    assert opened.seat_count == 2
    assert opened.waitlist_count == 1

    open_course =
      insert(:course,
        school_id: school_id,
        teacher_id: teacher.id,
        registration_state: "open",
        seat_count: 2,
        waitlist_count: 1
      )

    student1 = insert(:student, school_id: school_id)
    student2 = insert(:student, school_id: school_id)
    student3 = insert(:student, school_id: school_id)

    insert(:enrollment,
      school_id: school_id,
      course_id: open_course.id,
      student_id: student1.id,
      enrolled_on: ~D[2026-01-01]
    )

    insert(:enrollment,
      school_id: school_id,
      course_id: open_course.id,
      student_id: student2.id,
      enrolled_on: ~D[2026-01-02]
    )

    insert(:enrollment,
      school_id: school_id,
      course_id: open_course.id,
      student_id: student3.id,
      enrolled_on: ~D[2026-01-03]
    )

    assert {:ok, closed} = Courses.action("close-registration", open_course, %{}, authority)
    assert closed.registration_state == "closed"

    assert {:ok, deleted} = Courses.delete(course, authority)
    assert deleted.id == course.id
  end

  test "school and student facades delegate reads and CRUD mutations through sibling modules" do
    school = insert(:school, name: @school_name)
    school_id = school.id
    school_authority = Authority.new(:principal, Videdal.principal_id())

    student_authority =
      Authority.new(:school_admin, @school_admin_id, scopes: %{school_id: school_id})

    assert {:ok, found} = Schools.one(authority: Authority.system(), filter: %{id: school_id})
    assert found.id == school_id
    assert found.name == @school_name
    assert school_id in Enum.map(Schools.all(authority: Authority.system()), & &1.id)

    assert {:ok, created_school} = Schools.create(%{name: @school_name}, school_authority)
    assert created_school.name == @school_name

    assert {:ok, updated_school} =
             Schools.update(school, %{name: "Malmö Academy"}, school_authority)

    assert updated_school.name == "Malmö Academy"

    student = insert(:student, school_id: school_id, name: "Ada", active: true)

    assert {:ok, found} = Students.one(authority: Authority.system(), filter: %{id: student.id})
    assert found.id == student.id
    assert found.name == "Ada"
    assert student.id in Enum.map(Students.all(authority: Authority.system()), & &1.id)

    assert {:ok, created_student} =
             Students.create(
               %{name: "Ada", active: true, school_id: school_id},
               student_authority
             )

    assert created_student.name == "Ada"

    assert {:ok, updated_student} =
             Students.update(student, %{name: "Ada Lovelace", active: false}, student_authority)

    assert updated_student.name == "Ada Lovelace"
    assert updated_student.active == false

    assert {:ok, deleted_student} = Students.delete(student, student_authority)
    assert deleted_student.id == student.id

    assert {:ok, deleted_school} = Schools.delete(created_school, school_authority)
    assert deleted_school.id == created_school.id
  end

  test "grade facade delegates reads and CRUD mutations through sibling modules" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)
    student = insert(:student, school_id: school.id)
    course = insert(:course, school_id: school.id, teacher_id: teacher.id)

    grade =
      insert(:grade,
        school_id: school.id,
        student_id: student.id,
        course_id: course.id,
        score: 12
      )

    authority =
      Authority.new(:teacher, teacher.id, scopes: %{school_id: school.id, teacher_id: teacher.id})

    assert {:ok, found} = Grades.one(authority: Authority.system(), filter: %{id: grade.id})
    assert found.id == grade.id
    assert grade.id in Enum.map(Grades.all(authority: Authority.system()), & &1.id)

    assert {:ok, created_grade} =
             Grades.create(
               %{score: 12, school_id: school.id, student_id: student.id, course_id: course.id},
               authority
             )

    assert created_grade.score == 12

    assert {:ok, updated_grade} = Grades.update(grade, %{score: 15}, authority)
    assert updated_grade.score == 15

    assert {:ok, deleted_grade} = Grades.delete(grade, authority)
    assert deleted_grade.id == grade.id
  end

  test "enrollment and teacher facades delegate mutations through their writers" do
    school = insert(:school)
    teacher = insert(:teacher, school_id: school.id)
    student = insert(:student, school_id: school.id)
    course = insert(:course, school_id: school.id, teacher_id: teacher.id)
    school_id = school.id

    authority =
      Authority.new(:school_admin, @school_admin_id, scopes: %{school_id: school_id})

    enrollment =
      insert(:enrollment,
        school_id: school_id,
        student_id: student.id,
        course_id: course.id,
        enrolled_on: ~D[2026-01-01]
      )

    assert {:ok, found} =
             Enrollments.one(authority: Authority.system(), filter: %{id: enrollment.id})

    assert found.id == enrollment.id
    assert enrollment.id in Enum.map(Enrollments.all(authority: Authority.system()), & &1.id)

    assert {:ok, created_enrollment} =
             Enrollments.create(
               %{
                 school_id: school_id,
                 student_id: student.id,
                 course_id: course.id,
                 enrolled_on: ~D[2026-01-01]
               },
               authority
             )

    assert created_enrollment.school_id == school_id

    assert {:ok, updated_enrollment} =
             Enrollments.update(enrollment, %{enrolled_on: ~D[2026-02-01]}, authority)

    assert updated_enrollment.enrolled_on == ~D[2026-02-01]

    assert {:ok, deleted_enrollment} = Enrollments.delete(enrollment, authority)
    assert deleted_enrollment.id == enrollment.id

    assert {:ok, found} = Teachers.one(authority: Authority.system(), filter: %{id: teacher.id})
    assert found.id == teacher.id
    assert teacher.id in Enum.map(Teachers.all(authority: Authority.system()), & &1.id)

    assert {:ok, created_teacher} =
             Teachers.create(%{name: "Grace", school_id: school_id}, authority)

    assert created_teacher.name == "Grace"

    assert {:ok, updated_teacher} = Teachers.update(teacher, %{name: "Grace Hopper"}, authority)
    assert updated_teacher.name == "Grace Hopper"

    assert {:ok, deleted_teacher} = Teachers.delete(created_teacher, authority)
    assert deleted_teacher.id == created_teacher.id
  end
end
