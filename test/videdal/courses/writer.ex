defmodule Videdal.Courses.Writer do
  @moduledoc """
  Writer pipeline module for the Videdal `Courses` resource.
  """

  alias Hawk.MutationContext
  alias Hawk.RepositoryBoundary
  alias Videdal.{Course, Repo}
  alias Videdal.Courses.Policy

  use Hawk.Writer.Resource,
    model: Videdal.Course,
    repo: Videdal.Repo,
    policy: Videdal.Courses.Policy

  create do
    cast([:title, :school_id, :teacher_id])
    validate_required([:title, :school_id, :teacher_id])
  end

  update do
    cast([:title, :school_id, :teacher_id])
  end

  def delete(%Course{} = course, authority) do
    MutationContext.delete(course, authority)
    |> MutationContext.validate_policy(&Policy.delete?/1)
    |> RepositoryBoundary.delete(Repo)
  end
end
