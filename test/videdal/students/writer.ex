defmodule Videdal.Students.Writer do
  @moduledoc """
  Writer pipeline module for the Videdal `Students` resource.

  This is intentionally small, but it demonstrates the intended Hawk shape:
  build a mutation context, run guarded helpers, validate policy, then persist
  through the repository boundary.
  """

  alias Hawk.MutationContext
  alias Hawk.RepositoryBoundary
  alias Hawk.Writer
  alias Videdal.{Repo, Student}
  alias Videdal.Students.Policy

  def create(attrs, authority) do
    %Student{}
    |> MutationContext.new(attrs, authority, :create)
    |> Writer.defaults(active: true)
    |> Writer.cast([:name, :active, :school_id])
    |> Writer.validate_required([:name, :school_id])
    |> MutationContext.validate_policy(&Policy.create?/1)
    |> RepositoryBoundary.insert(Repo)
  end

  def update(%Student{} = student, attrs, authority) do
    student
    |> MutationContext.new(attrs, authority, :update)
    |> Writer.cast([:name, :active, :school_id])
    |> MutationContext.validate_policy(&Policy.update?/1)
    |> RepositoryBoundary.update(Repo)
  end

  def delete(%Student{} = student, authority) do
    student
    |> MutationContext.new(%{}, authority, :delete)
    |> MutationContext.validate_policy(&Policy.delete?/1)
    |> RepositoryBoundary.delete(Repo)
  end
end
