defmodule Videdal.Courses.Reader do
  @moduledoc """
  Reader declaration module for the Videdal `Courses` resource.
  """

  use Hawk.Reader.Resource,
    repo: Videdal.Repo,
    schema: Videdal.Course,
    policy: Videdal.Courses.Policy

  filter(:id)
  filter(:school_id)
  filter(:teacher_id)

  preload(:school)
  preload(:teacher)

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
