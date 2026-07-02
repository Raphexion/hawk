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
end
