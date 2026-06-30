defmodule Videdal.SchoolPolicy do
  @moduledoc """
  Example read policy that converts Videdal authorities into Hawk filters.
  """

  alias Hawk.Authority

  def read_filter(%Authority{} = authority) do
    cond do
      Authority.system?(authority) ->
        :all

      authority.role == :principal ->
        :all

      authority.role == :school_admin ->
        scoped_filter(authority, [:school_id])

      authority.role == :teacher ->
        scoped_filter(authority, [:school_id, :teacher_id])

      authority.role == :student ->
        scoped_filter(authority, [:school_id, :student_id], %{active: true})

      true ->
        :none
    end
  end

  defp scoped_filter(authority, required_scopes, extra_filter \\ %{}) do
    Enum.reduce_while(required_scopes, extra_filter, fn scope, filter ->
      case Authority.fetch_scope(authority, scope) do
        {:ok, value} -> {:cont, Map.put(filter, scope, value)}
        :error -> {:halt, :none}
      end
    end)
  end
end
