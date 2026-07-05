defmodule Videdal.Parents.Reader do
  @moduledoc """
  Reader declaration module for the Videdal `Parents` resource.
  """

  use Hawk.Reader.Resource,
    repo: Videdal.Repo,
    schema: Videdal.Parent,
    policy: Videdal.Parents.Policy

  filter(:id)
  filter(:school_id)

  filter :parent_id do
    fn {:eq, parent_id} ->
      dynamic([parent], parent.id == ^parent_id)
    end
  end
end
