defmodule Videdal.Enrollments.Reader do
  @moduledoc """
  Reader declaration module for the Videdal `Enrollments` resource.
  """

  use Hawk.Reader.Resource,
    repo: Videdal.Repo,
    schema: Videdal.Enrollment,
    policy: Videdal.Enrollments.Policy

  filter(:id)
  filter(:school_id)
  filter(:student_id)
  filter(:course_id)

  preload(:school)
  preload(:student)
  preload(:course)

  filter :enrolled_on_or_after do
    fn
      {:eq, date} -> dynamic([enrollment], enrollment.enrolled_on >= ^date)
      {:gte, date} -> dynamic([enrollment], enrollment.enrolled_on >= ^date)
    end
  end

  attach :student, when_filter: [:student_name] do
    join(query, :inner, [root: enrollment], student in assoc(enrollment, :student), as: :student)
  end

  attach :course, when_filter: [:course_title] do
    join(query, :inner, [root: enrollment], course in assoc(enrollment, :course), as: :course)
  end

  filter :student_name do
    fn {:eq, student_name} ->
      dynamic([student: student], student.name == ^student_name)
    end
  end

  filter :course_title do
    fn {:eq, course_title} ->
      dynamic([course: course], course.title == ^course_title)
    end
  end
end
