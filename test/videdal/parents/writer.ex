defmodule Videdal.Parents.Writer do
  @moduledoc false

  use Hawk.Writer.Resource,
    model: Videdal.Parent,
    repo: Videdal.Repo,
    policy: Videdal.Parents.Policy

  create do
    cast([:name, :school_id])
  end

  update do
    cast([:name, :school_id])
  end

  def delete(%Videdal.Parent{} = parent, authority) do
    Hawk.MutationContext.delete(parent, authority)
    |> Hawk.MutationContext.validate_policy(&Videdal.Parents.Policy.delete?/1)
    |> Hawk.RepositoryBoundary.delete(Videdal.Repo)
  end
end
