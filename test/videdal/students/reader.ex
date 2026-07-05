defmodule Videdal.Students.Reader do
  @moduledoc """
  Reader declaration module for the Videdal `Students` resource.
  """

  use Hawk.Reader.Resource,
    repo: Videdal.Repo,
    schema: Videdal.Student,
    policy: Videdal.Students.Policy

  filter(:id)
  filter(:school_id)
  filter(:active)

  preload(:school)

  filter :student_id do
    fn {:eq, student_id} ->
      dynamic([student], student.id == ^student_id)
    end
  end

  attach :school, when_filter: [:school_name] do
    join(query, :inner, [root: student], school in assoc(student, :school), as: :school)
  end

  attach :parent_student, when_filter: [:parent_id] do
    join(query, :inner, [root: student], parent_student in assoc(student, :parent_students),
      as: :parent_student
    )
  end

  filter :parent_id do
    fn {:eq, parent_id} ->
      dynamic([parent_student: parent_student], parent_student.parent_id == ^parent_id)
    end
  end

  filter :school_name do
    fn {:eq, school_name} ->
      dynamic([school: school], school.name == ^school_name)
    end
  end
end
