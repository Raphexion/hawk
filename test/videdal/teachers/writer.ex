defmodule Videdal.Teachers.Writer do
  @moduledoc """
  Writer pipeline module for the Videdal `Teachers` resource.
  """

  alias Hawk.MutationContext
  alias Hawk.RepositoryBoundary
  alias Hawk.Writer
  alias Videdal.{Repo, Teacher}
  alias Videdal.Teachers.Policy

  def create(attrs, authority) do
    %Teacher{}
    |> MutationContext.new(attrs, authority, :create)
    |> Writer.cast([:name, :school_id])
    |> Writer.validate_required([:name, :school_id])
    |> MutationContext.validate_policy(&Policy.create?/1)
    |> RepositoryBoundary.insert(Repo)
  end

  def update(%Teacher{} = teacher, attrs, authority) do
    teacher
    |> MutationContext.new(attrs, authority, :update)
    |> Writer.cast([:name, :school_id])
    |> MutationContext.validate_policy(&Policy.update?/1)
    |> RepositoryBoundary.update(Repo)
  end

  def delete(%Teacher{} = teacher, authority) do
    teacher
    |> MutationContext.new(%{}, authority, :delete)
    |> MutationContext.validate_policy(&Policy.delete?/1)
    |> RepositoryBoundary.delete(Repo)
  end
end
