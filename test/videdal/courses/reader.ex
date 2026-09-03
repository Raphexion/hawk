defmodule Videdal.Courses.Reader do
  @moduledoc """
  Reader declaration module for the Videdal `Courses` resource.
  """

  use Hawk.Reader.Resource,
    repo: Videdal.Repo,
    schema: Videdal.Course

  filter(:id)
  filter(:school_id)
  filter(:teacher_id)
  filter(:title)

  filter :similar_to_course_id do
    fn {:eq, course_id} ->
      dynamic([root: course], course.id != ^course_id)
    end
  end

  sort(:id)
  sort(:title)

  rank_scope :largest_waitlist do
    order_by(query, [root: course], desc: course.waitlist_count)
  end

  preload(:school)
  preload(:teacher)
  preload(:grades)
  preload(:enrollments)

  attach :school, when_filter: [:school_name] do
    join(query, :inner, [root: course], school in assoc(course, :school), as: :school)
  end

  attach :teacher, when_filter: [:teacher_name] do
    join(query, :inner, [root: course], teacher in assoc(course, :teacher), as: :teacher)
  end

  filter :school_name do
    fn {:eq, school_name} ->
      dynamic([school: school], school.name == ^school_name)
    end
  end

  filter :teacher_name do
    fn {:eq, teacher_name} ->
      dynamic([teacher: teacher], teacher.name == ^teacher_name)
    end
  end
end
