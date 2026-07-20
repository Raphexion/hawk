defmodule Videdal.Courses.Writer do
  @moduledoc """
  Writer pipeline module for the Videdal `Courses` resource.
  """

  alias Hawk.MutationContext
  alias Hawk.RepositoryBoundary
  alias Hawk.Writer
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

  def change_update(%Course{} = course, attrs, authority) do
    course
    |> update_context(attrs, authority)
    |> Writer.changeset()
  end

  def update(%Course{} = course, attrs, authority) do
    course
    |> update_context(attrs, authority)
    |> RepositoryBoundary.update(Repo)
  end

  defp update_context(%Course{} = course, attrs, authority) do
    course
    |> MutationContext.update(attrs, authority)
    |> Writer.cast([:title, :school_id, :teacher_id])
    |> MutationContext.validate_policy(&Policy.update?/1)
  end

  def delete(%Course{} = course, authority) do
    MutationContext.delete(course, authority)
    |> MutationContext.validate_policy(&Policy.delete?/1)
    |> RepositoryBoundary.delete(Repo)
  end
end
