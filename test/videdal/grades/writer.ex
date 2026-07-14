defmodule Videdal.Grades.Writer do
  @moduledoc """
  Writer pipeline module for the Videdal `Grades` resource.
  """

  alias Hawk.MutationContext
  alias Hawk.RepositoryBoundary
  alias Hawk.Writer
  alias Videdal.{Grade, Grades.Policy, Repo}

  def create(attrs, authority) do
    MutationContext.create(%Grade{}, attrs, authority)
    |> Writer.cast([:score, :school_id, :student_id, :course_id])
    |> Writer.validate_required([:score, :school_id, :student_id, :course_id])
    |> MutationContext.validate_policy(&Policy.create?/1)
    |> RepositoryBoundary.insert(Repo)
  end

  def update(%Grade{} = grade, attrs, authority) do
    MutationContext.update(grade, attrs, authority)
    |> Writer.cast([:score, :school_id, :student_id, :course_id])
    |> MutationContext.validate_policy(&Policy.update?/1)
    |> RepositoryBoundary.update(Repo)
  end

  def delete(%Grade{} = grade, authority) do
    MutationContext.delete(grade, authority)
    |> MutationContext.validate_policy(&Policy.delete?/1)
    |> RepositoryBoundary.delete(Repo)
  end
end
