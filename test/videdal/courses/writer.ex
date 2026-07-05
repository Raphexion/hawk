defmodule Videdal.Courses.Writer do
  @moduledoc """
  Writer pipeline module for the Videdal `Courses` resource.
  """

  alias Hawk.MutationContext
  alias Hawk.RepositoryBoundary
  alias Hawk.Writer
  alias Videdal.{Course, Repo}
  alias Videdal.Courses.Policy

  def create(attrs, authority) do
    MutationContext.create(%Course{}, attrs, authority)
    |> Writer.cast([:title, :school_id, :teacher_id])
    |> Writer.validate_required([:title, :school_id, :teacher_id])
    |> MutationContext.validate_policy(&Policy.create?/1)
    |> RepositoryBoundary.insert(Repo)
  end

  def update(%Course{} = course, attrs, authority) do
    MutationContext.update(course, attrs, authority)
    |> Writer.cast([:title, :school_id, :teacher_id])
    |> MutationContext.validate_policy(&Policy.update?/1)
    |> RepositoryBoundary.update(Repo)
  end

  def delete(%Course{} = course, authority) do
    MutationContext.delete(course, authority)
    |> MutationContext.validate_policy(&Policy.delete?/1)
    |> RepositoryBoundary.delete(Repo)
  end
end
