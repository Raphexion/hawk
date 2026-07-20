defmodule Videdal.Enrollments.Writer do
  @moduledoc """
  Writer pipeline module for the Videdal `Enrollments` resource.
  """

  alias Hawk.MutationContext
  alias Hawk.RepositoryBoundary
  alias Videdal.{Enrollment, Repo}
  alias Videdal.Enrollments.Policy

  use Hawk.Writer.Resource,
    model: Videdal.Enrollment,
    repo: Videdal.Repo,
    policy: Videdal.Enrollments.Policy

  create do
    cast([:school_id, :student_id, :course_id, :enrolled_on])
    validate_required([:school_id, :student_id, :course_id])
  end

  update do
    cast([:school_id, :student_id, :course_id, :enrolled_on])
  end

  def delete(%Enrollment{} = enrollment, authority) do
    MutationContext.delete(enrollment, authority)
    |> MutationContext.validate_policy(&Policy.delete?/1)
    |> RepositoryBoundary.delete(Repo)
  end
end
