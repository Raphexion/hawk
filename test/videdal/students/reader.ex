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

  filter :student_id do
    fn {:eq, student_id} ->
      dynamic([student], student.id == ^student_id)
    end
  end
end
