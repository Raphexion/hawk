defmodule Videdal.Teachers.Writer do
  @moduledoc """
  Writer pipeline module for the Videdal `Teachers` resource.
  """

  alias Hawk.MutationContext
  alias Hawk.RepositoryBoundary
  alias Videdal.{Repo, Teacher}
  alias Videdal.Teachers.Policy

  use Hawk.Writer.Resource,
    model: Videdal.Teacher,
    repo: Videdal.Repo,
    policy: Videdal.Teachers.Policy

  create do
    cast([:name, :school_id])
    validate_required([:name, :school_id])
  end

  update do
    cast([:name, :school_id])
  end

  def delete(%Teacher{} = teacher, authority) do
    MutationContext.delete(teacher, authority)
    |> MutationContext.validate_policy(&Policy.delete?/1)
    |> RepositoryBoundary.delete(Repo)
  end
end
