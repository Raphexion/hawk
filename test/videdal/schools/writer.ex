defmodule Videdal.Schools.Writer do
  @moduledoc """
  Writer pipeline module for the Videdal `Schools` resource.
  """

  alias Hawk.MutationContext
  alias Hawk.RepositoryBoundary
  alias Videdal.{Repo, School}
  alias Videdal.Schools.Policy

  use Hawk.Writer.Resource,
    model: Videdal.School,
    repo: Videdal.Repo,
    policy: Videdal.Schools.Policy

  create do
    cast([:name])
    validate_required([:name])
  end

  update do
    cast([:name])
  end

  def delete(%School{} = school, authority) do
    MutationContext.delete(school, authority)
    |> MutationContext.validate_policy(&Policy.delete?/1)
    |> RepositoryBoundary.delete(Repo)
  end
end
