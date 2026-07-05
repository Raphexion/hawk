defmodule Videdal.Repo do
  @moduledoc """
  Minimal repo double used by Hawk's repository-boundary tests.

  Real applications provide an `Ecto.Repo`. This module keeps the example
  database-free while showing the callbacks Hawk expects from a host repo.
  """

  alias Ecto.Changeset

  def all(query) do
    send(self(), {:videdal_repo, :all, query})
    Process.get({__MODULE__, :all_results}, [])
  end

  def transaction(fun) when is_function(fun, 0) do
    send(self(), {:videdal_repo, :transaction})
    {:ok, fun.()}
  end

  def preload(results, preloads) do
    send(self(), {:videdal_repo, :preload, results, preloads})
    results
  end

  def insert(%Changeset{} = changeset, _opts \\ []) do
    send(self(), {:videdal_repo, :insert, changeset})
    apply_changeset(changeset)
  end

  def update(%Changeset{} = changeset, _opts \\ []) do
    send(self(), {:videdal_repo, :update, changeset})
    apply_changeset(changeset)
  end

  def delete(model, _opts \\ []) when is_struct(model) do
    send(self(), {:videdal_repo, :delete, model})
    {:ok, model}
  end

  defp apply_changeset(%Changeset{valid?: true} = changeset) do
    {:ok, Changeset.apply_changes(changeset)}
  end

  defp apply_changeset(%Changeset{} = changeset), do: {:error, changeset}
end
