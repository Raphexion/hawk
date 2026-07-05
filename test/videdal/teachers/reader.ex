defmodule Videdal.Teachers.Reader do
  @moduledoc """
  Reader declaration module for the Videdal `Teachers` resource.
  """

  use Hawk.Reader.Resource,
    repo: Videdal.Repo,
    schema: Videdal.Teacher,
    policy: Videdal.Teachers.Policy

  filter(:id)
  filter(:school_id)

  filter :teacher_id do
    fn {:eq, teacher_id} ->
      dynamic([teacher], teacher.id == ^teacher_id)
    end
  end

  attach :school, when_filter: [:school_name] do
    join(query, :inner, [root: teacher], school in assoc(teacher, :school), as: :school)
  end

  filter :school_name do
    fn {:eq, school_name} ->
      dynamic([school: school], school.name == ^school_name)
    end
  end
end
