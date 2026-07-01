defmodule Videdal.Schools.Writer do
  @moduledoc """
  Writer pipeline module for the Videdal `Schools` resource.
  """

  alias Hawk.MutationContext
  alias Hawk.RepositoryBoundary
  alias Hawk.Writer
  alias Videdal.{Repo, School}
  alias Videdal.Schools.Policy

  def create(attrs, authority) do
    %School{}
    |> MutationContext.new(attrs, authority, :create)
    |> Writer.cast([:name])
    |> Writer.validate_required([:name])
    |> MutationContext.validate_policy(&Policy.create?/1)
    |> RepositoryBoundary.insert(Repo)
  end

  def update(%School{} = school, attrs, authority) do
    school
    |> MutationContext.new(attrs, authority, :update)
    |> Writer.cast([:name])
    |> MutationContext.validate_policy(&Policy.update?/1)
    |> RepositoryBoundary.update(Repo)
  end

  def delete(%School{} = school, authority) do
    school
    |> MutationContext.new(%{}, authority, :delete)
    |> MutationContext.validate_policy(&Policy.delete?/1)
    |> RepositoryBoundary.delete(Repo)
  end
end
