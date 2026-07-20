defmodule Videdal.Students.Writer do
  @moduledoc """
  Writer pipeline module for the Videdal `Students` resource.

  This is intentionally small, but it demonstrates the intended Hawk shape:
  declare the guarded create/update pipelines once, then let Hawk generate both
  persistence functions and non-persisting form changeset helpers.
  """

  alias Hawk.MutationContext
  alias Hawk.RepositoryBoundary
  alias Videdal.{Repo, Student}
  alias Videdal.Students.Policy

  use Hawk.Writer.Resource,
    model: Videdal.Student,
    repo: Videdal.Repo,
    policy: Videdal.Students.Policy

  create do
    defaults(active: true)
    cast([:name, :active, :school_id])
    validate_required([:name, :school_id])
  end

  update do
    cast([:name, :active, :school_id])
  end

  def delete(%Student{} = student, authority) do
    MutationContext.delete(student, authority)
    |> MutationContext.validate_policy(&Policy.delete?/1)
    |> RepositoryBoundary.delete(Repo)
  end
end
