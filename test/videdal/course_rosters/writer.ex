defmodule Videdal.CourseRosters.Writer do
  @moduledoc false

  alias Hawk.MutationContext
  alias Hawk.RepositoryBoundary
  alias Videdal.{CourseRoster, Repo}
  alias Videdal.CourseRosters.Policy

  def create(attrs, authority) do
    MutationContext.create(%CourseRoster{}, attrs, authority)
    |> MutationContext.validate_policy(&Policy.create?/1)
    |> RepositoryBoundary.insert(Repo)
  end

  def update(%CourseRoster{} = roster, attrs, authority) do
    MutationContext.update(roster, attrs, authority)
    |> MutationContext.validate_policy(&Policy.update?/1)
    |> RepositoryBoundary.update(Repo)
  end

  def delete(%CourseRoster{} = roster, authority) do
    MutationContext.delete(roster, authority)
    |> MutationContext.validate_policy(&Policy.delete?/1)
    |> RepositoryBoundary.delete(Repo)
  end
end
