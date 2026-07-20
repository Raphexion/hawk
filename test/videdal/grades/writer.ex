defmodule Videdal.Grades.Writer do
  @moduledoc """
  Writer pipeline module for the Videdal `Grades` resource.
  """

  alias Hawk.MutationContext
  alias Hawk.RepositoryBoundary
  alias Videdal.{Grade, Grades.Policy, Repo}

  use Hawk.Writer.Resource,
    model: Videdal.Grade,
    repo: Videdal.Repo,
    policy: Videdal.Grades.Policy

  create do
    cast([:score, :school_id, :student_id, :course_id])
    validate_required([:score, :school_id, :student_id, :course_id])
  end

  update do
    cast([:score, :school_id, :student_id, :course_id])
  end

  def delete(%Grade{} = grade, authority) do
    MutationContext.delete(grade, authority)
    |> MutationContext.validate_policy(&Policy.delete?/1)
    |> RepositoryBoundary.delete(Repo)
  end
end
