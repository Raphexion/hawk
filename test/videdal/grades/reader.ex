defmodule Videdal.Grades.Reader do
  @moduledoc """
  Reader declaration module for the Videdal `Grades` resource.
  """

  use Hawk.Reader.Resource,
    repo: Videdal.Repo,
    schema: Videdal.Grade,
    policy: Videdal.Grades.Policy

  filter(:id)
  filter(:school_id)
  filter(:student_id)
  filter(:course_id)
  filter(:score)

  preload(:student, policy: Videdal.Students.Policy)
  preload(:course, policy: Videdal.Courses.Policy)

  attach :student, when_filter: [:student_name, :parent_id] do
    join(query, :inner, [root: grade], student in assoc(grade, :student), as: :student)
  end

  attach :parent_student, when_filter: [:parent_id] do
    join(query, :inner, [student: student], parent_student in assoc(student, :parent_students),
      as: :parent_student
    )
  end

  attach :course, when_filter: [:course_title, :teacher_id] do
    join(query, :inner, [root: grade], course in assoc(grade, :course), as: :course)
  end

  filter :student_name do
    fn {:eq, student_name} ->
      dynamic([student: student], student.name == ^student_name)
    end
  end

  filter :parent_id do
    fn {:eq, parent_id} ->
      dynamic([parent_student: parent_student], parent_student.parent_id == ^parent_id)
    end
  end

  filter :course_title do
    fn {:eq, course_title} ->
      dynamic([course: course], course.title == ^course_title)
    end
  end

  filter :teacher_id do
    fn {:eq, teacher_id} ->
      dynamic([course: course], course.teacher_id == ^teacher_id)
    end
  end
end
