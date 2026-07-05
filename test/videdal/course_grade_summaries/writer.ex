defmodule Videdal.CourseGradeSummaries.Writer do
  @moduledoc """
  Writer module for read-only course grade summaries.

  Every operation validates the read-only policy and stops before persistence.
  """

  alias Hawk.MutationContext
  alias Hawk.RepositoryBoundary
  alias Videdal.CourseGradeSummaries.Policy
  alias Videdal.{CourseGradeSummary, Repo}

  def create(attrs, authority) do
    MutationContext.create(%CourseGradeSummary{}, attrs, authority)
    |> MutationContext.validate_policy(&Policy.create?/1)
    |> RepositoryBoundary.insert(Repo)
  end

  def update(%CourseGradeSummary{} = summary, attrs, authority) do
    MutationContext.update(summary, attrs, authority)
    |> MutationContext.validate_policy(&Policy.update?/1)
    |> RepositoryBoundary.update(Repo)
  end

  def delete(%CourseGradeSummary{} = summary, authority) do
    MutationContext.delete(summary, authority)
    |> MutationContext.validate_policy(&Policy.delete?/1)
    |> RepositoryBoundary.delete(Repo)
  end
end
