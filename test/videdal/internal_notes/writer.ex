defmodule Videdal.InternalNotes.Writer do
  @moduledoc false

  use Hawk.Writer.Resource,
    model: Videdal.InternalNote,
    repo: Videdal.Repo,
    policy: Videdal.InternalNotes.Policy

  create do
    cast([:body])
  end

  update do
    cast([:body])
  end

  def delete(%Videdal.InternalNote{} = note, authority) do
    Hawk.MutationContext.delete(note, authority)
    |> Hawk.MutationContext.validate_policy(&Videdal.InternalNotes.Policy.delete?/1)
    |> Hawk.RepositoryBoundary.delete(Videdal.Repo)
  end
end
