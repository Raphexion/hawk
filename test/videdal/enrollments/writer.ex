defmodule Videdal.Enrollments.Writer do
  @moduledoc """
  Writer pipeline module for the Videdal `Enrollments` resource.
  """

  alias Hawk.MutationContext
  alias Hawk.RepositoryBoundary
  alias Hawk.Writer
  alias Videdal.{Enrollment, Repo}
  alias Videdal.Enrollments.Policy

  def create(attrs, authority) do
    MutationContext.create(%Enrollment{}, attrs, authority)
    |> Writer.cast([:school_id, :student_id, :course_id, :enrolled_on])
    |> Writer.validate_required([:school_id, :student_id, :course_id])
    |> MutationContext.validate_policy(&Policy.create?/1)
    |> RepositoryBoundary.insert(Repo)
  end

  def update(%Enrollment{} = enrollment, attrs, authority) do
    MutationContext.update(enrollment, attrs, authority)
    |> Writer.cast([:school_id, :student_id, :course_id, :enrolled_on])
    |> MutationContext.validate_policy(&Policy.update?/1)
    |> RepositoryBoundary.update(Repo)
  end

  def delete(%Enrollment{} = enrollment, authority) do
    MutationContext.delete(enrollment, authority)
    |> MutationContext.validate_policy(&Policy.delete?/1)
    |> RepositoryBoundary.delete(Repo)
  end
end
