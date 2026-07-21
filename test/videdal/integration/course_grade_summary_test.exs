defmodule Videdal.Integration.CourseGradeSummaryTest.Reader do
  @moduledoc false

  use Hawk.Reader.Resource,
    repo: Videdal.SandboxRepo,
    schema: Videdal.CourseGradeSummary,
    policy: Videdal.CourseGradeSummaries.Policy

  filter(:school_id)
  filter(:course_id)
end

defmodule Videdal.Integration.CourseGradeSummaryTest do
  use Videdal.DatabaseCase, async: false

  alias Hawk.Authority
  alias Videdal.{Course, Grade, SandboxRepo, School, Student, Teacher}
  alias Videdal.Integration.CourseGradeSummaryTest.Reader

  setup do
    Videdal.DatabaseCase.reset_schema!()
    {:ok, seed_school()}
  end

  test "course grade summaries are readable by everyone", data do
    student =
      Authority.new(:student, data.student.id, scopes: %{school_id: data.school.id, student_id: data.student.id})

    unknown = Authority.new(:unknown, 1)

    assert [%Videdal.CourseGradeSummary{grade_count: 2, average_score: 11.0}] =
             Reader.all(authority: student, filter: %{course_id: data.course.id})

    assert [%Videdal.CourseGradeSummary{grade_count: 2, average_score: 11.0}] =
             Reader.all(authority: unknown, filter: %{course_id: data.course.id})
  end

  defp seed_school do
    school = SandboxRepo.insert!(%School{name: "Videdal Skole"})
    teacher = SandboxRepo.insert!(%Teacher{name: "Ms. Curie", school_id: school.id})
    student = SandboxRepo.insert!(%Student{name: "Ada", school_id: school.id})
    other_student = SandboxRepo.insert!(%Student{name: "Grace", school_id: school.id})

    course =
      SandboxRepo.insert!(%Course{title: "Math", school_id: school.id, teacher_id: teacher.id})

    SandboxRepo.insert!(%Grade{
      score: 12,
      school_id: school.id,
      student_id: student.id,
      course_id: course.id
    })

    SandboxRepo.insert!(%Grade{
      score: 10,
      school_id: school.id,
      student_id: other_student.id,
      course_id: course.id
    })

    %{school: school, student: student, course: course}
  end
end
